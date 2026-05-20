import Cocoa
import Carbon

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Configuration
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let HOTKEY_KEYCODE: UInt32 = 17          // 'T' key
let HOTKEY_SCREENSHOT: UInt32 = 15       // 'R' key
let HOTKEY_MODIFIERS: UInt32 = UInt32(optionKey)  // Option (⌥)
let SERVER = "http://127.0.0.1:19876"

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Design Tokens
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TC {
    static let green  = NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
    static let red    = NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
    // text hierarchy: primary → body → secondary → hint
    static let primary = NSColor(white: 0.06, alpha: 1)   // question — loudest
    static let text    = NSColor(white: 0.13, alpha: 1)
    static let body    = NSColor(white: 0.24, alpha: 1)    // answer — readable
    static let sub     = NSColor(white: 0.40, alpha: 1)    // input text
    static let muted   = NSColor(white: 0.55, alpha: 1)    // context quote
    static let faint   = NSColor(white: 0.72, alpha: 1)    // hint
    static let rule    = NSColor(white: 0, alpha: 0.07)
    static let ctxBg   = NSColor(white: 0, alpha: 0.035)   // context block background
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - App Delegate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var hotKeyScreenshotRef: EventHotKeyRef?
    var capturePanel: CapturePanel?
    var resultBubble: ResultBubble?
    var selectionToolbar: SelectionToolbar?
    var prevAppBundleId: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXIsProcessTrusted()
        fputs("[TC] AX trusted on launch: \(trusted)\n", stderr)

        setupMenubar()
        registerHotkey()
        resultBubble = ResultBubble()
        setupSelectionToolbar()
    }

    func setupSelectionToolbar() {
        selectionToolbar = SelectionToolbar()

        // Pin: save selected text directly as thought
        selectionToolbar?.onPin = { [weak self] text in
            self?.sendToServer(thought: text, selectedText: "",
                               appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown",
                               windowTitle: self?.getWindowTitle() ?? "",
                               browserURL: "")
        }

        // Expand: open capture panel with selected text
        selectionToolbar?.onExpand = { [weak self] text, pos in
            guard let self = self else { return }
            self.prevAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            let windowTitle = self.getWindowTitle()
            let browserURL = self.getBrowserURL(appName: appName)
            let editable = self.lastSelectionEditable

            if self.capturePanel == nil { self.capturePanel = CapturePanel() }
            self.capturePanel?.show(selectedText: text, anchorPoint: pos) { [weak self] thought in
                self?.sendToServer(thought: thought, selectedText: text,
                                   appName: appName, windowTitle: windowTitle,
                                   browserURL: browserURL, editable: editable)
            }
        }

        selectionToolbar?.startMonitoring()
    }

    // MARK: Menubar

    func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "TC"

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture Thought (\u{2325}T)",
                                     action: #selector(triggerCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        let screenshotItem = NSMenuItem(title: "Screenshot + Comment (\u{2325}R)",
                                        action: #selector(triggerScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: Global Hotkey (Carbon)

    func registerHotkey() {
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        InstallEventHandler(
            GetApplicationEventTarget(), hotKeyHandler, 1, &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), nil)

        // ⌥T — thought capture
        var hotKeyID1 = EventHotKeyID()
        hotKeyID1.signature = OSType(0x54435F48)  // "TC_H"
        hotKeyID1.id = 1
        RegisterEventHotKey(HOTKEY_KEYCODE, HOTKEY_MODIFIERS, hotKeyID1,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        // ⌥R — screenshot + comment
        var hotKeyID2 = EventHotKeyID()
        hotKeyID2.signature = OSType(0x54435F48)
        hotKeyID2.id = 2
        RegisterEventHotKey(HOTKEY_SCREENSHOT, HOTKEY_MODIFIERS, hotKeyID2,
                            GetApplicationEventTarget(), 0, &hotKeyScreenshotRef)
    }

    // MARK: Capture Flow

    @objc func triggerCapture() {
        let prevApp = NSWorkspace.shared.frontmostApplication
        prevAppBundleId = prevApp?.bundleIdentifier

        let mousePos = NSEvent.mouseLocation
        let selectedText = getSelectedText()
        let editable = lastSelectionEditable
        let appName = prevApp?.localizedName ?? "Unknown"
        let windowTitle = getWindowTitle()
        let browserURL = getBrowserURL(appName: appName)

        if capturePanel == nil { capturePanel = CapturePanel() }
        capturePanel?.show(selectedText: selectedText, anchorPoint: mousePos) { [weak self] thought in
            self?.sendToServer(thought: thought, selectedText: selectedText,
                               appName: appName, windowTitle: windowTitle, browserURL: browserURL,
                               editable: editable)
        }
    }

    // MARK: Screenshot Capture Flow (⌥R)

    @objc func triggerScreenshot() {
        let prevApp = NSWorkspace.shared.frontmostApplication
        let appName = prevApp?.localizedName ?? "Unknown"
        let windowTitle = getWindowTitle()
        let browserURL = getBrowserURL(appName: appName)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let tmpPath = "/tmp/tc_screenshot_\(timestamp).png"

        // Force previous app to front via AppleScript (more reliable than activate)
        if let bundleId = prevApp?.bundleIdentifier {
            _ = runOsascript(
                "tell application id \"\(bundleId)\" to activate")
        }

        // Wait until the app is actually frontmost, then screenshot
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Poll until previous app is frontmost (max 1s)
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    == prevApp?.bundleIdentifier { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            Thread.sleep(forTimeInterval: 0.15)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-i", "-x", tmpPath]
            try? proc.run()
            proc.waitUntilExit()

            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: tmpPath) else { return }
                let mousePos = NSEvent.mouseLocation
                if self?.capturePanel == nil { self?.capturePanel = CapturePanel() }
                self?.capturePanel?.show(selectedText: "", anchorPoint: mousePos,
                                        screenshotPath: tmpPath) { thought in
                    self?.sendToServer(thought: thought, selectedText: "",
                                       appName: appName, windowTitle: windowTitle,
                                       browserURL: browserURL, screenshotPath: tmpPath)
                }
            }
        }
    }

    // MARK: Selected Text (Accessibility API + Cmd+C fallback)

    var lastSelectionEditable: Bool = false

    func getSelectedText() -> String {
        func dbg(_ msg: String) { fputs("[TC] \(msg)\n", stderr) }

        let trusted = AXIsProcessTrusted()
        lastSelectionEditable = false

        // Method 1: Accessibility API (if permitted)
        if trusted {
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let pid = frontApp.processIdentifier
                let appEl = AXUIElementCreateApplication(pid)
                var focused: AnyObject?
                let r1 = AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused)
                if r1 == .success, let el = focused {
                    // Check if the focused element is editable
                    let axEl = el as! AXUIElement
                    var roleVal: AnyObject?
                    AXUIElementCopyAttributeValue(axEl, kAXRoleAttribute as CFString, &roleVal)
                    let role = roleVal as? String ?? ""
                    let editableRoles = ["AXTextField", "AXTextArea", "AXComboBox"]
                    if editableRoles.contains(role) {
                        lastSelectionEditable = true
                    } else {
                        // Some apps use AXWebArea but contenteditable
                        var editableVal: AnyObject?
                        let r3 = AXUIElementCopyAttributeValue(axEl, "AXEditable" as CFString, &editableVal)
                        if r3 == .success, let editable = editableVal as? Bool, editable {
                            lastSelectionEditable = true
                        }
                    }
                    dbg("role=\(role) editable=\(lastSelectionEditable)")

                    var sel: AnyObject?
                    let r2 = AXUIElementCopyAttributeValue(axEl, kAXSelectedTextAttribute as CFString, &sel)
                    if r2 == .success, let text = sel as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            dbg("Got selected text via AX (editable=\(lastSelectionEditable))")
                            return trimmed
                        }
                    }
                }
            }
        }

        // Method 2: CGEvent Cmd+C (needs Accessibility permission)
        if trusted {
            let pb = NSPasteboard.general
            let oldCount = pb.changeCount
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
            usleep(200_000)

            if pb.changeCount != oldCount {
                let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    dbg("Got context from clipboard (\(text.count) chars)")
                    return text
                }
            }
        }

        // Fallback: read clipboard directly (user can Cmd+C before ⌥T)
        let clipText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clipText.isEmpty && clipText.count < 2000 {
            dbg("Got context from clipboard fallback (\(clipText.count) chars)")
            return clipText
        }

        dbg("No selected text found")
        return ""
    }

    // MARK: Context Helpers

    func getBrowserURL(appName: String) -> String {
        let script: String
        switch appName {
        case "Safari":
            script = "tell application \"Safari\" to get URL of current tab of front window"
        case "Google Chrome", "Microsoft Edge", "Brave Browser", "Arc":
            script = "tell application \"\(appName)\" to get URL of active tab of front window"
        default: return ""
        }
        return runOsascript(script)
    }

    func getWindowTitle() -> String {
        return runOsascript(
            "tell application \"System Events\" to get name of first window " +
            "of (first process whose frontmost is true)")
    }

    private func runOsascript(_ script: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        let deadline = DispatchTime.now() + .seconds(2)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            proc.waitUntilExit()
            done.signal()
        }
        if done.wait(timeout: deadline) == .timedOut {
            proc.terminate()
            fputs("[TC] osascript timed out\n", stderr)
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Send to Server

    func sendToServer(thought: String, selectedText: String,
                      appName: String, windowTitle: String, browserURL: String,
                      editable: Bool = false, screenshotPath: String? = nil) {
        let url = browserURL.isEmpty ? "app://\(appName)" : browserURL
        // Get the NEXT colorIndex (the one that will be used after intensify)
        let bubble = resultBubble?.dotWin.contentView as? ThoughtBubbleView
        let nextColorIdx = ((bubble?.colorIdx ?? 0) + 1) % 8
        var payload: [String: Any?] = [
            "input": thought,
            "selectedText": selectedText.isEmpty ? nil : selectedText,
            "url": url,
            "title": windowTitle.isEmpty ? appName : windowTitle,
            "source": "global",
            "app": appName,
            "editable": editable,
            "colorIndex": nextColorIdx,
        ]
        // Attach screenshot as base64
        if let path = screenshotPath,
           let data = FileManager.default.contents(atPath: path) {
            payload["screenshot"] = data.base64EncodedString()
            // Clean up temp file
            try? FileManager.default.removeItem(atPath: path)
        }
        guard let body = try? JSONSerialization.data(
            withJSONObject: payload.compactMapValues { $0 }) else { return }

        if let debugStr = String(data: body, encoding: .utf8) {
            fputs("[TC] payload: \(debugStr.prefix(200))\n", stderr)
        }

        var req = URLRequest(url: URL(string: "\(SERVER)/handle")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                fputs("[TC] response: err=\(err?.localizedDescription ?? "nil") dataLen=\(data?.count ?? 0)\n", stderr)
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let respType = json["type"] as? String ?? ""
                    fputs("[TC] respType=\(respType) panelAlive=\(self?.capturePanel?.isOpen ?? false)\n", stderr)
                    if respType == "edit" {
                        self?.capturePanel?.close()
                        self?.resultBubble?.playSuccessFeedback()
                    } else if respType == "question" {
                        if let taskId = json["taskId"] as? String {
                            self?.pollQuestionAnswer(taskId)
                        }
                    } else if respType == "polish" {
                        self?.capturePanel?.close()
                        self?.resultBubble?.prevAppBundleId = self?.prevAppBundleId
                        let msg = json["message"] as? String ?? "working..."
                        self?.resultBubble?.setWorkingTask(msg)
                        if let taskId = json["taskId"] as? String {
                            self?.resultBubble?.pollTask(taskId, type: respType)
                        }
                    } else if respType == "task" || respType == "plan" || respType == "command" {
                        self?.capturePanel?.close()
                        let msg = json["message"] as? String ?? "working..."
                        self?.resultBubble?.setWorkingTask(msg)
                        if let taskId = json["taskId"] as? String {
                            self?.resultBubble?.pollTask(taskId)
                        }
                    } else {
                        self?.capturePanel?.close()
                        let savedTo = json["savedTo"] as? String ?? ""
                        self?.resultBubble?.addItem(text: thought, savedTo: savedTo, ok: true)
                    }
                } else {
                    self?.capturePanel?.close()
                    self?.resultBubble?.addItem(text: thought, savedTo: "", ok: false)
                }
            }
        }.resume()
    }
    // MARK: Question Answer Polling

    private var questionTimer: Timer?

    func pollQuestionAnswer(_ taskId: String) {
        fputs("[TC] pollQuestionAnswer: taskId=\(taskId)\n", stderr)
        questionTimer?.invalidate()
        questionTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] timer in
            guard let url = URL(string: "\(SERVER)/tasks") else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tasks = json["tasks"] as? [[String: Any]] else { return }
                let task = tasks.first { ($0["id"] as? String) == taskId }
                let status = task?["status"] as? String ?? "running"
                fputs("[TC] poll \(taskId): status=\(status)\n", stderr)
                if status != "running" {
                    DispatchQueue.main.async {
                        timer.invalidate()
                        self?.questionTimer = nil
                        fputs("[TC] poll done, panelAlive=\(self?.capturePanel?.isOpen ?? false)\n", stderr)
                        if status == "done", let answer = task?["answer"] as? String {
                            self?.capturePanel?.showAnswer(answer)
                            self?.resultBubble?.playSuccessFeedback()
                        } else {
                            self?.capturePanel?.showAnswer("(failed)")
                        }
                    }
                }
            }.resume()
        }
    }
}

// Carbon callback — dispatches ⌥T (id=1) or ⌥R (id=2) to AppDelegate
func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?,
                   userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let ud = userData, let ev = event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(ev, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let delegate = Unmanaged<AppDelegate>.fromOpaque(ud).takeUnretainedValue()
    let sel: Selector = hotKeyID.id == 2
        ? #selector(AppDelegate.triggerScreenshot)
        : #selector(AppDelegate.triggerCapture)
    delegate.performSelector(onMainThread: sel, with: nil, waitUntilDone: false)
    return noErr
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Capture Panel
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// NSPanel subclass that accepts keyboard input despite borderless style.
class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Floating input bar — appears near selected text, captures a thought.
/// Uses NSTextView for auto-wrapping multi-line input.
class CapturePanel: NSObject, NSTextStorageDelegate {
    private var panel: KeyPanel?
    private var textView: NSTextView?
    private var scrollView: NSScrollView?
    private var card: NSView?
    private var hintLabel: NSTextField?
    private var quoteLabel: NSTextField?
    private var ctxBoxView: NSView?
    private var onSubmit: ((String) -> Void)?

    private var escMonitor: Any?
    private var clickMonitor: Any?

    private let pw: CGFloat = 440
    private let baseInputH: CGFloat = 24
    private let maxInputH: CGFloat = 120
    private var hasQuote = false
    private var quotedText = ""
    private var hasScreenshot = false
    private var screenshotView: NSImageView?
    private var anchorY: CGFloat = 0
    private var isAIMode = false
    private var answerPhase = false  // true during showWorking/showAnswer — blocks resizeToFit
    private var topRegionH: CGFloat = 10

    func show(selectedText: String, anchorPoint: NSPoint,
              screenshotPath: String? = nil,
              completion: @escaping (String) -> Void) {
        onSubmit = completion
        close()
        guard let screen = NSScreen.main else { return }

        hasQuote = !selectedText.isEmpty
        quotedText = selectedText
        hasScreenshot = screenshotPath != nil
        let thumbH: CGFloat = hasScreenshot ? 140 : 0
        quoteOffsetFromTop = 36
        topRegionH = hasQuote ? 46 : 10   // topPad(10) + box(26) + gap(10), or just topPad(10)
        let ph: CGFloat = topRegionH + baseInputH + 14 + thumbH
        anchorY = anchorPoint.y

        // Position below the mouse
        var px = anchorPoint.x - pw / 2
        var py = anchorPoint.y - ph - 10
        px = max(12, min(px, screen.frame.width - pw - 12))
        py = max(12, min(py, screen.frame.height - ph - 12))

        let p = KeyPanel(contentRect: NSMakeRect(px, py, pw, ph),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true

        // White card
        let c = NSView(frame: NSMakeRect(0, 0, pw, ph))
        c.wantsLayer = true
        c.layer?.cornerRadius = 12
        c.layer?.backgroundColor = NSColor.white.cgColor
        c.layer?.shadowColor = NSColor.black.cgColor
        c.layer?.shadowOpacity = 0.10
        c.layer?.shadowRadius = 16
        c.layer?.shadowOffset = CGSize(width: 0, height: -3)
        card = c

        var topY = ph

        // Screenshot thumbnail preview
        if hasScreenshot, let path = screenshotPath,
           let img = NSImage(contentsOfFile: path) {
            topY -= (thumbH + 8)
            let imgView = NSImageView(frame: NSMakeRect(12, topY, pw - 24, thumbH))
            imgView.image = img
            imgView.imageScaling = .scaleProportionallyUpOrDown
            imgView.imageAlignment = .alignCenter
            imgView.wantsLayer = true
            imgView.layer?.cornerRadius = 8
            imgView.layer?.masksToBounds = true
            imgView.layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
            c.addSubview(imgView)
            screenshotView = imgView
        }

        // Selected text preview
        if hasQuote {
            let txt = Self.truncate(selectedText, max: 55)
            let ctxY = ph - 10 - 26  // 10px from top, 26px box height

            let ctxBox = NSView(frame: NSMakeRect(12, ctxY - 2, pw - 24, 26))
            ctxBox.wantsLayer = true
            ctxBox.layer?.backgroundColor = TC.ctxBg.cgColor
            ctxBox.layer?.cornerRadius = 8
            ctxBox.identifier = NSUserInterfaceItemIdentifier("ctxBox")
            c.addSubview(ctxBox)
            ctxBoxView = ctxBox

            let label = NSTextField(labelWithString: txt)
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = TC.muted
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSMakeRect(20, ctxY + 2, pw - 40, 14)
            c.addSubview(label)
            quoteLabel = label
        }

        // NSTextView in NSScrollView for auto-wrapping input
        let inputY: CGFloat = 14
        let sv = NSScrollView(frame: NSMakeRect(10, inputY, pw - 24, baseInputH))
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let tv = NSTextView(frame: NSMakeRect(0, 0, pw - 24, baseInputH))
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textColor = TC.sub
        tv.drawsBackground = false
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 2, height: 2)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: pw - 32, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textStorage?.delegate = self
        sv.documentView = tv
        c.addSubview(sv)
        scrollView = sv
        textView = tv

        isAIMode = false

        // Placeholder
        let placeholder = NSTextField(labelWithString: "记个想法… 或 /指令 问AI")
        placeholder.font = NSFont.systemFont(ofSize: 13)
        placeholder.textColor = TC.faint
        placeholder.frame = NSMakeRect(14, inputY + 2, 260, 20)
        placeholder.tag = 999
        c.addSubview(placeholder)

        // Hint
        let hint = NSTextField(labelWithString: "\u{21B5} save \u{00B7} esc")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = TC.faint
        hint.frame = NSMakeRect(pw - 80, 4, 70, 12)
        hint.alignment = .right
        c.addSubview(hint)
        hintLabel = hint

        p.contentView = c

        // Fade in
        c.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        p.makeFirstResponder(tv)
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            c.animator().alphaValue = 1
        }


        // Keyboard: Esc to close, Enter to submit
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if ev.keyCode == 53 { self?.close(); return nil }
            if ev.keyCode == 36 && !ev.modifierFlags.contains(.shift) {
                self?.submit(); return nil
            }
            return ev
        }

        // Click outside to close
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    // MARK: Auto-resize as user types

    private var updatingStyle = false

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard !updatingStyle else { return }
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
            self?.updateAIMode()
        }
    }

    private let aiColor = NSColor(red: 0.55, green: 0.36, blue: 0.85, alpha: 1)

    private func updateAIMode() {
        guard let tv = textView, let c = card else { return }
        let wantsAI = tv.string.hasPrefix("/") || tv.string.hasPrefix("／")
        if wantsAI != isAIMode {
            isAIMode = wantsAI
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                if wantsAI {
                    c.layer?.borderWidth = 1.5
                    c.layer?.borderColor = aiColor.withAlphaComponent(0.35).cgColor
                    c.layer?.shadowColor = aiColor.cgColor
                    c.layer?.shadowOpacity = 0.15
                    c.layer?.shadowRadius = 12
                } else {
                    c.layer?.borderWidth = 0
                    c.layer?.shadowColor = NSColor.black.cgColor
                    c.layer?.shadowOpacity = 0.10
                    c.layer?.shadowRadius = 16
                }
            }
            hintLabel?.stringValue = wantsAI
                ? "\u{21B5} ask AI \u{00B7} esc"
                : "\u{21B5} save \u{00B7} esc close"
        }

        if wantsAI && tv.string.count >= 1 {
            updatingStyle = true
            let full = tv.textStorage!
            let range = NSRange(location: 0, length: full.length)
            full.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: range)
            full.addAttribute(.foregroundColor, value: TC.sub, range: range)
            // "/" — larger, bold, purple, with trailing space
            let slashRange = NSRange(location: 0, length: 1)
            full.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: slashRange)
            full.addAttribute(.foregroundColor, value: aiColor, range: slashRange)
            full.addAttribute(.kern, value: 3, range: slashRange)
            updatingStyle = false
        }
    }

    private func resizeToFit() {
        if answerPhase {
            fputs("[TC] resizeToFit BLOCKED (answerPhase)\n", stderr)
            return
        }
        guard let tv = textView, let sv = scrollView,
              let p = panel, let c = card else { return }

        // Hide/show placeholder
        if let ph = c.viewWithTag(999) {
            ph.isHidden = !tv.string.isEmpty
        }

        // Calculate needed height for text
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let usedRect = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        let neededH = max(baseInputH, min(ceil(usedRect.height) + 8, maxInputH))

        let inputY: CGFloat = 14
        let thumbH: CGFloat = hasScreenshot ? 148 : 0
        let totalH = topRegionH + neededH + inputY + thumbH

        let dy = totalH - c.frame.height
        if abs(dy) < 1 { return }

        var frame = p.frame
        frame.origin.y -= dy
        frame.size.height += dy
        p.setFrame(frame, display: true)

        c.frame = NSMakeRect(0, 0, pw, totalH)
        sv.frame = NSMakeRect(10, inputY, pw - 24, neededH)
        sv.hasVerticalScroller = neededH >= maxInputH

        repositionTopElements(totalH)
        if let h = hintLabel {
            h.frame = NSMakeRect(pw - 100, inputY + 4, 90, 12)
        }
    }

    private func submit() {
        let typed = textView?.string
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // If empty but has quoted selected text, save the selected text as thought
        let text = typed.isEmpty ? quotedText : typed
        guard !text.isEmpty else { close(); return }
        fputs("[TC] submit: \(text)\n", stderr)
        if text.hasPrefix("/") || text.hasPrefix("／") {
            showWorking()
        } else {
            close()
        }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        onSubmit?(text)
    }

    var isOpen: Bool { panel != nil }

    func close() {
        fputs("[TC] CapturePanel.close()\n", stderr)
        dotsTimer?.invalidate(); dotsTimer = nil
        streamTimer?.invalidate(); streamTimer = nil
        panel?.close(); panel = nil
        screenshotView = nil
        ctxBoxView = nil
        questionLabel = nil
        isAIMode = false
        answerPhase = false
        submittedQuestion = ""
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    // MARK: Answer Display

    private var questionLabel: NSTextField?
    private var dotsTimer: Timer?
    private var streamTimer: Timer?
    private var submittedQuestion: String = ""

    // Quote offset from top — set once in show(), never changes
    private var quoteOffsetFromTop: CGFloat = 0

    private func repositionTopElements(_ totalH: CGFloat) {
        if hasQuote {
            let ctxY = totalH - quoteOffsetFromTop
            ctxBoxView?.isHidden = false
            ctxBoxView?.frame = NSMakeRect(12, ctxY - 2, pw - 24, 26)
            quoteLabel?.isHidden = false
            quoteLabel?.font = NSFont.systemFont(ofSize: 11)
            quoteLabel?.frame = NSMakeRect(20, ctxY + 2, pw - 40, 14)
        }
    }

    func showWorking() {
        guard let p = panel, let c = card, let tv = textView, let sv = scrollView else { return }

        answerPhase = true
        submittedQuestion = tv.string
        tv.textStorage?.setAttributedString(NSAttributedString(string: ""))
        if let ph = c.viewWithTag(999) { ph.isHidden = true }
        questionLabel?.removeFromSuperview()
        screenshotView?.isHidden = true

        let ql = NSTextField(labelWithString: "")
        ql.lineBreakMode = .byTruncatingTail
        ql.attributedStringValue = Self.styledQuestion(submittedQuestion)
        c.addSubview(ql, positioned: .above, relativeTo: nil)
        questionLabel = ql

        // Question goes where input was
        let qY = sv.frame.origin.y + 2
        ql.frame = NSMakeRect(16, qY, pw - 32, 16)

        let dotsH: CGFloat = 20
        let totalH = quoteOffsetFromTop + 16 + 12 + dotsH + 12

        var frame = p.frame
        let dy = totalH - frame.size.height
        frame.origin.y -= dy
        frame.size.height = totalH
        p.setFrame(frame, display: true)
        c.frame = NSMakeRect(0, 0, pw, totalH)

        repositionTopElements(totalH)
        let newQY = totalH - quoteOffsetFromTop - 16 - 12
        ql.frame = NSMakeRect(16, newQY, pw - 32, 16)

        sv.frame = NSMakeRect(16, 12, pw - 32, dotsH)
        sv.wantsLayer = true
        sv.layer?.masksToBounds = true
        tv.isEditable = false
        startDotsAnimation(tv)
        hintLabel?.isHidden = true
    }

    private func startDotsAnimation(_ tv: NSTextView) {
        dotsTimer?.invalidate()
        var tick = 0
        dotsTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak tv] _ in
            guard let tv = tv else { return }
            tick += 1
            let dots = String(repeating: "·", count: (tick % 3) + 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: TC.muted
            ]
            tv.textStorage?.setAttributedString(NSAttributedString(string: dots, attributes: attrs))
        }
    }

    func showAnswer(_ text: String) {
        dotsTimer?.invalidate(); dotsTimer = nil

        guard let p = panel, let c = card, let tv = textView, let sv = scrollView else { return }

        tv.textStorage?.setAttributedString(NSAttributedString(string: ""))

        c.subviews.filter { $0.identifier?.rawValue == "sep" }.forEach { $0.removeFromSuperview() }
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = TC.rule.cgColor
        sep.identifier = NSUserInterfaceItemIdentifier("sep")
        c.addSubview(sep)

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }

        let qOffFromTop = quoteOffsetFromTop + 16 + 12
        let footerH: CGFloat = 24
        let maxAnswerH: CGFloat = 200

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 3
        let answerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: TC.body,
            .paragraphStyle: paraStyle
        ]
        let chars = Array(text)
        var idx = 0

        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) {
            [weak self, weak tv, weak sv, weak p, weak c] timer in
            guard let self = self, let tv = tv, let sv = sv, let p = p, let c = c else {
                timer.invalidate(); return
            }
            let chunkSize = max(1, chars.count / 60)
            let end = min(idx + chunkSize, chars.count)
            let chunk = String(chars[idx..<end])
            tv.textStorage?.append(NSAttributedString(string: chunk, attributes: answerAttrs))
            idx = end

            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            let usedRect = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
            let answerH = max(18, min(ceil(usedRect.height) + 10, maxAnswerH))
            let totalH = qOffFromTop + 1 + 6 + answerH + footerH

            var frame = p.frame
            let dy = totalH - frame.size.height
            if abs(dy) > 1 {
                frame.origin.y -= dy
                frame.size.height = totalH
                p.setFrame(frame, display: true)
                c.frame = NSMakeRect(0, 0, self.pw, totalH)
            }

            self.repositionTopElements(totalH)
            let qY = totalH - self.quoteOffsetFromTop - 16 - 12
            self.questionLabel?.frame = NSMakeRect(16, qY, self.pw - 32, 16)

            let sepY = qY - 10
            c.subviews.first { $0.identifier?.rawValue == "sep" }?.frame =
                NSMakeRect(16, sepY, self.pw - 32, 0.5)

            sv.frame = NSMakeRect(16, footerH, self.pw - 32, sepY - 6 - footerH)
            sv.hasVerticalScroller = answerH >= maxAnswerH

            self.hintLabel?.isHidden = false
            self.hintLabel?.frame = NSMakeRect(self.pw - 70, 2, 60, 12)
            self.hintLabel?.stringValue = "esc"
            self.hintLabel?.font = NSFont.systemFont(ofSize: 10)
            self.hintLabel?.textColor = TC.faint

            tv.scrollToEndOfDocument(nil)

            if idx >= chars.count {
                timer.invalidate()
                self.streamTimer = nil
            }
        }
    }

    private static let aiColorStatic = NSColor(red: 0.55, green: 0.36, blue: 0.85, alpha: 1)

    static func styledQuestion(_ text: String) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: TC.text
        ]
        let result = NSMutableAttributedString(string: text, attributes: base)
        if text.hasPrefix("/") {
            let slashAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: aiColorStatic,
                .kern: 2
            ]
            result.setAttributes(slashAttrs, range: NSRange(location: 0, length: 1))
        }
        return result
    }

    static func truncate(_ s: String, max: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        if flat.count <= max { return flat }
        let half = (max - 3) / 2
        return "\(flat.prefix(half))...\(flat.suffix(half))"
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Result Bubble
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ResultItem {
    let id: Int
    let text: String
    let savedTo: String
    let ok: Bool
    let time: String
    let color: NSColor  // matches the bubble color at time of capture
}

/// Draggable thought-bubble icon in screen corner.
/// Hover to see recent captures; click a row to open in Obsidian.
class ResultBubble {
    var dotWin: NSWindow!
    private var popWin: NSWindow!
    private var items: [ResultItem] = []
    private var nextId = 1
    private var hideTimer: Timer?
    private var dragMonitor: Any?

    private let dotSize: CGFloat = 48
    private let popWidth: CGFloat = 320

    init() {
        guard let screen = NSScreen.main else { return }

        // Draggable bubble icon
        let x = screen.frame.width - dotSize - 16
        dotWin = NSWindow(contentRect: NSMakeRect(x, 16, dotSize, dotSize),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        dotWin.level = .floating
        dotWin.isOpaque = false
        dotWin.backgroundColor = .clear
        dotWin.hasShadow = false
        dotWin.isMovableByWindowBackground = true

        let bubble = ThoughtBubbleView(frame: NSMakeRect(0, 0, dotSize, dotSize))
        bubble.onEnter = { [weak self] in self?.showPopover() }
        bubble.onExit  = { [weak self] in self?.scheduleDismiss() }
        dotWin.contentView = bubble

        // Gentle floating animation
        startFloating()

        // Popover (hidden until hover)
        popWin = NSWindow(contentRect: NSMakeRect(0, 0, popWidth, 100),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        popWin.level = .floating
        popWin.isOpaque = false
        popWin.backgroundColor = .clear
        popWin.hasShadow = true

        let container = TrackView(frame: NSMakeRect(0, 0, popWidth, 100))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.08
        container.layer?.shadowRadius = 14
        container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        container.onEnter = { [weak self] in self?.cancelDismiss() }
        container.onExit  = { [weak self] in self?.scheduleDismiss() }
        popWin.contentView = container

        // Hide popover when user starts dragging the dot
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] event in
            if let self = self, self.popWin.isVisible {
                self.popWin.orderOut(nil)
                self.cancelDismiss()
            }
            return event
        }
    }

    // MARK: Animations

    /// Gentle bobbing — animates the layer, not the window, so dragging works.
    func startFloating() {
        guard let layer = dotWin.contentView?.layer else { return }
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -2.5
        float.toValue = 2.5
        float.duration = 2.4
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(float, forKey: "float")
    }

    /// Visual + audio feedback when a thought is saved.
    func playSuccessFeedback() {
        guard let bubble = dotWin.contentView as? ThoughtBubbleView else { return }

        // Orb intensifies + shifts color
        bubble.intensify()

        // Scale bounce on the whole view
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.25, 0.93, 1.05, 1.0]
        bounce.keyTimes = [0, 0.15, 0.45, 0.7, 1.0]
        bounce.duration = 0.45
        bubble.layer?.add(bounce, forKey: "bounce")

        NSSound(named: "Bottle")?.play()
    }

    // MARK: Show / Hide

    private func showPopover() {
        cancelDismiss()
        fetchPlan()  // async — will rebuild when data arrives
        guard !items.isEmpty || !planItems.isEmpty else { return }
        rebuildPopover()
        positionPopover()

        // Add as child window so it follows when dot is dragged
        if !(dotWin.childWindows?.contains(popWin) ?? false) {
            dotWin.addChildWindow(popWin, ordered: .above)
        }
        popWin.orderFront(nil)
    }

    /// Position popover to the left or right of dot, whichever fits on screen.
    private func positionPopover() {
        let dot = dotWin.frame
        let pop = popWin.frame
        let screen = dotWin.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let gap: CGFloat = 6

        // Try left first
        var x = dot.minX - pop.width - gap
        if x < screen.visibleFrame.minX {
            // Doesn't fit left, put it right
            x = dot.maxX + gap
        }
        // Vertical: align bottom edges, clamp to screen
        var y = dot.minY
        y = max(screen.visibleFrame.minY, min(y, screen.visibleFrame.maxY - pop.height))

        popWin.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismiss() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.dotWin.removeChildWindow(self.popWin)
            self.popWin.orderOut(nil)
        }
    }

    private func cancelDismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: Data

    func addItem(text: String, savedTo: String, ok: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Animate first — color shifts to the NEW color for this thought
        if ok { playSuccessFeedback() }

        // Now capture the NEW color (post-intensify) as this thought's identity
        let bubbleColor: NSColor
        if let bubble = dotWin.contentView as? ThoughtBubbleView {
            bubbleColor = bubble.currentColor
        } else {
            bubbleColor = TC.green
        }

        let item = ResultItem(id: nextId, text: text, savedTo: savedTo,
                              ok: ok, time: formatter.string(from: Date()),
                              color: bubbleColor)
        nextId += 1
        items.insert(item, at: 0)
        if items.count > 20 { items = Array(items.prefix(20)) }
        dotWin.orderFront(nil)
        if popWin.isVisible { rebuildPopover() }
    }

    // MARK: Popover Layout

    private var planItems: [[String: Any]] = []
    private var planFilePath: String = ""
    private var workingTask: String? = nil
    private var pollTimer: Timer? = nil
    var prevAppBundleId: String?

    func setWorkingTask(_ label: String) {
        workingTask = label
        playSuccessFeedback()
        if popWin.isVisible { rebuildPopover() }
    }

    func pollTask(_ taskId: String, type: String = "task") {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let url = URL(string: "\(SERVER)/tasks") else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tasks = json["tasks"] as? [[String: Any]] else { return }
                let task = tasks.first { ($0["id"] as? String) == taskId }
                let status = task?["status"] as? String ?? "running"
                if status != "running" {
                    DispatchQueue.main.async {
                        timer.invalidate()
                        self?.pollTimer = nil
                        self?.workingTask = nil
                        if status == "done" {
                            if type == "question", let answer = task?["answer"] as? String {
                                // Show answer in bubble
                                self?.addItem(text: answer, savedTo: "", ok: true)
                            } else if type == "polish", let polished = task?["polished"] as? String {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(polished, forType: .string)
                                self?.pasteBackToApp()
                                self?.addItem(text: "✓ polished", savedTo: "", ok: true)
                            } else {
                                let savedTo = task?["savedTo"] as? String ?? ""
                                self?.addItem(text: "✓ done", savedTo: savedTo, ok: true)
                            }
                        } else {
                            self?.addItem(text: "✗ failed", savedTo: "", ok: false)
                        }
                    }
                }
            }.resume()
        }
    }

    private func pasteBackToApp() {
        guard let bundleId = prevAppBundleId else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else { return }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func rebuildPopover() {
        guard let container = popWin.contentView as? TrackView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let rowH: CGFloat = 32
        let pad: CGFloat = 8
        let sectionGap: CGFloat = 6

        let visiblePlans = Array(planItems.enumerated())
        let visibleThoughts = items
        let planCount = min(visiblePlans.count, 6)
        let thoughtCount = min(visibleThoughts.count, 8)

        // Calculate total height
        var totalH = pad
        let hasWorking = workingTask != nil
        if hasWorking { totalH += 24 }
        if planCount > 0 {
            totalH += 18
            totalH += CGFloat(planCount) * rowH
            if thoughtCount > 0 { totalH += sectionGap + 1 }
        }
        if thoughtCount > 0 {
            totalH += 18
            totalH += CGFloat(thoughtCount) * rowH
        }
        totalH += 8

        container.frame = NSMakeRect(0, 0, popWidth, totalH)
        var y = totalH - pad

        // ── Working indicator ──
        if hasWorking {
            y -= 20
            let workLabel = NSTextField(labelWithString: "⏳ \(workingTask ?? "working...")")
            workLabel.font = rounded(size: 11, weight: .medium)
            workLabel.textColor = NSColor(red: 0.88, green: 0.55, blue: 0.12, alpha: 1)
            workLabel.frame = NSMakeRect(10, y, popWidth - 20, 16)
            container.addSubview(workLabel)
        }

        // Priority colors for numbers
        let priorityColors: [String: NSColor] = [
            "urgent-important": NSColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 1),
            "urgent":           NSColor(red: 0.88, green: 0.55, blue: 0.12, alpha: 1),
            "important":        NSColor(red: 0.30, green: 0.50, blue: 0.82, alpha: 1),
        ]

        // ── Plan Section ──
        if planCount > 0 {
            y -= 16
            let headerRow = ClickableRow(frame: NSMakeRect(4, y, popWidth - 8, 16))
            let planPath = planFilePath
            headerRow.onClick = { ResultBubble.openInObsidian(path: planPath) }
            let header = NSTextField(labelWithString: "TODAY'S PLAN  ↗")
            header.font = rounded(size: 9, weight: .medium)
            header.textColor = TC.muted
            header.frame = NSMakeRect(8, 1, 120, 13)
            headerRow.addSubview(header)
            container.addSubview(headerRow)

            for i in 0..<planCount {
                y -= rowH
                let (origIdx, plan) = visiblePlans[i]
                let rawText = plan["text"] as? String ?? ""
                let done = plan["done"] as? Bool ?? false

                var displayText = rawText
                var priority = ""
                for tag in ["#urgent-important", "#urgent", "#important"] {
                    if displayText.contains(tag) {
                        priority = tag.replacingOccurrences(of: "#", with: "")
                        displayText = displayText.replacingOccurrences(of: tag, with: "")
                    }
                }
                if let r = displayText.range(of: #"[（(][^)）]*[)）]\s*$"#, options: .regularExpression) {
                    displayText = String(displayText[..<r.lowerBound])
                }
                displayText = displayText.trimmingCharacters(in: .whitespaces)
                var indexLabel = "\(i + 1)"
                if let m = displayText.range(of: #"^[\d]+\.[\d]*\s*"#, options: .regularExpression) {
                    indexLabel = String(displayText[m]).trimmingCharacters(in: .whitespaces)
                    if indexLabel.hasSuffix(".") { indexLabel = String(indexLabel.dropLast()) }
                    displayText = String(displayText[m.upperBound...])
                }

                let row = ClickableRow(frame: NSMakeRect(4, y, popWidth - 8, rowH))
                row.wantsLayer = true
                row.layer?.cornerRadius = 6
                let toggleIdx = origIdx
                row.onClick = { [weak self] in self?.togglePlanItem(toggleIdx) }

                // Colored number or ✓
                let numColor = done ? TC.green : (priorityColors[priority] ?? TC.muted)
                let num = NSTextField(labelWithString: done ? "✓" : indexLabel)
                num.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
                num.textColor = numColor
                num.alignment = .center
                num.frame = NSMakeRect(4, (rowH - 14) / 2, 20, 14)
                row.addSubview(num)

                // Task text
                let label = NSTextField(labelWithString: displayText)
                label.font = rounded(size: 12)
                label.textColor = done ? TC.faint : TC.text
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSMakeRect(26, (rowH - 14) / 2, popWidth - 46, 14)
                if done {
                    let a = NSMutableAttributedString(string: displayText)
                    a.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: a.length))
                    a.addAttribute(.foregroundColor, value: TC.faint, range: NSRange(location: 0, length: a.length))
                    label.attributedStringValue = a
                }
                row.addSubview(label)

                container.addSubview(row)
                if i < planCount - 1 {
                    let sep = NSView(frame: NSMakeRect(26, y, popWidth - 48, 0.5))
                    sep.wantsLayer = true
                    sep.layer?.backgroundColor = NSColor(white: 0, alpha: 0.04).cgColor
                    container.addSubview(sep)
                }
            }
            if thoughtCount > 0 {
                y -= sectionGap
                let div = NSView(frame: NSMakeRect(10, y, popWidth - 20, 0.5))
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor(white: 0, alpha: 0.06).cgColor
                container.addSubview(div)
            }
        }

        // ── Thoughts Section ──
        if thoughtCount > 0 {
            y -= 16
            let header = NSTextField(labelWithString: "THOUGHTS")
            header.font = rounded(size: 9, weight: .medium)
            header.textColor = TC.muted
            header.frame = NSMakeRect(10, y + 1, popWidth - 20, 13)
            container.addSubview(header)

            for i in 0..<thoughtCount {
                let item = visibleThoughts[i]
                y -= rowH

                let row = ClickableRow(frame: NSMakeRect(4, y, popWidth - 8, rowH))
                let path = item.savedTo
                let text = item.text
                row.onClick = { ResultBubble.openInObsidian(path: path, searchText: text) }
                row.wantsLayer = true
                row.layer?.cornerRadius = 6

                // Color dot
                let dot = NSView(frame: NSMakeRect(8, (rowH - 6) / 2, 6, 6))
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.layer?.backgroundColor = (item.ok ? item.color : TC.red).cgColor
                row.addSubview(dot)

                // Text
                let label = NSTextField(labelWithString: item.text)
                label.font = rounded(size: 12)
                label.textColor = TC.text
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSMakeRect(22, (rowH - 14) / 2, popWidth - 76, 14)
                row.addSubview(label)

                // Time
                let time = NSTextField(labelWithString: item.time)
                time.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
                time.textColor = TC.faint
                time.alignment = .right
                time.frame = NSMakeRect(popWidth - 54, (rowH - 12) / 2, 36, 12)
                row.addSubview(time)

                container.addSubview(row)
                if i < thoughtCount - 1 {
                    let sep = NSView(frame: NSMakeRect(22, y, popWidth - 44, 0.5))
                    sep.wantsLayer = true
                    sep.layer?.backgroundColor = NSColor(white: 0, alpha: 0.04).cgColor
                    container.addSubview(sep)
                }
            }
        }

        popWin.setContentSize(NSSize(width: popWidth, height: totalH))
        if popWin.isVisible { positionPopover() }
    }

    // MARK: Font helper
    private func rounded(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let sys = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = sys.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: desc, size: size) ?? sys
        }
        return sys
    }

    // MARK: Plan sync

    private func fetchPlan() {
        guard let url = URL(string: "\(SERVER)/plan") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }
            DispatchQueue.main.async {
                self?.planItems = items
                self?.planFilePath = json["file"] as? String ?? ""
                if self?.popWin.isVisible == true { self?.rebuildPopover() }
            }
        }.resume()
    }

    private func togglePlanItem(_ index: Int) {
        guard let url = URL(string: "\(SERVER)/plan/toggle") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["index": index])
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["ok"] as? Bool == true else { return }
            let nowDone = json["done"] as? Bool ?? false
            DispatchQueue.main.async {
                if nowDone { self?.playCompletionEffect(index: index) }
                self?.fetchPlan()
            }
        }.resume()
    }

    private func playCompletionEffect(index: Int) {
        // Sound
        NSSound(named: "Pop")?.play()

        // Bounce the bubble
        if let bubble = dotWin.contentView as? ThoughtBubbleView {
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [1.0, 1.15, 0.95, 1.05, 1.0]
            bounce.keyTimes = [0, 0.2, 0.5, 0.75, 1.0]
            bounce.duration = 0.35
            bubble.layer?.add(bounce, forKey: "complete")
        }
    }

    // MARK: Open in Obsidian

    static func openInObsidian(path: String, searchText: String = "") {
        guard !path.isEmpty else { return }
        let file = path.components(separatedBy: " + ").first ?? path
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file
        // First open the file
        if let url = URL(string: "obsidian://open?vault=obsidian-brain&file=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        // Then search within the file to scroll to the thought
        if !searchText.isEmpty {
            // Take first 30 chars of thought as search query, enough to locate uniquely
            let query = String(searchText.prefix(30))
            let searchQuery = "path:\"\(file)\" \"\(query)\""
            if let sq = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let searchUrl = URL(string: "obsidian://search?vault=obsidian-brain&query=\(sq)") {
                // Small delay so the file opens first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSWorkspace.shared.open(searchUrl)
                }
            }
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - UI Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Clickable row with hover highlight and pointer cursor.
class ClickableRow: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.03).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }
}

/// View with mouse enter/exit callbacks.
class TrackView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// Simple gradient circle with soft breathing pulse.
class ThoughtBubbleView: TrackView {
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit ThoughtCapture",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private var circle: CAGradientLayer!
    var colorIdx = 0
    private var colorIndex: Int {
        get { colorIdx }
        set { colorIdx = newValue }
    }

    // (top, bottom) linear gradient pairs
    private let palette: [(NSColor, NSColor)] = [
        (NSColor(red: 0.96, green: 0.65, blue: 0.45, alpha: 1),   // peach
         NSColor(red: 0.90, green: 0.42, blue: 0.50, alpha: 1)),   // coral
        (NSColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1),   // light blue
         NSColor(red: 0.38, green: 0.50, blue: 0.85, alpha: 1)),   // blue
        (NSColor(red: 0.85, green: 0.70, blue: 0.95, alpha: 1),   // lilac
         NSColor(red: 0.62, green: 0.45, blue: 0.82, alpha: 1)),   // purple
        (NSColor(red: 0.60, green: 0.90, blue: 0.75, alpha: 1),   // mint
         NSColor(red: 0.35, green: 0.70, blue: 0.62, alpha: 1)),   // green
        (NSColor(red: 0.95, green: 0.80, blue: 0.45, alpha: 1),   // golden
         NSColor(red: 0.88, green: 0.58, blue: 0.30, alpha: 1)),   // amber
        (NSColor(red: 0.70, green: 0.85, blue: 0.55, alpha: 1),   // lime
         NSColor(red: 0.48, green: 0.72, blue: 0.40, alpha: 1)),   // olive
        (NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1),   // pink
         NSColor(red: 0.82, green: 0.35, blue: 0.48, alpha: 1)),   // raspberry
        (NSColor(red: 0.50, green: 0.75, blue: 0.88, alpha: 1),   // sky
         NSColor(red: 0.32, green: 0.58, blue: 0.75, alpha: 1)),   // steel
    ]

    /// The current dominant color (bottom gradient), exposed for popover dots.
    var currentColor: NSColor { palette[colorIndex].1 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        let s: CGFloat = 28
        let cx = frame.width / 2
        let cy = frame.height / 2
        let (top, bot) = palette[0]

        circle = CAGradientLayer()
        circle.frame = CGRect(x: cx - s/2, y: cy - s/2, width: s, height: s)
        circle.cornerRadius = s / 2
        circle.colors = [top.cgColor, bot.cgColor]
        circle.startPoint = CGPoint(x: 0.5, y: 1.0)
        circle.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(circle)

        // Gentle breathing
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.95; pulse.toValue = 1.05
        pulse.duration = 3.0; pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circle.add(pulse, forKey: "pulse")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    func intensify() {
        colorIndex = (colorIndex + 1) % palette.count
        let (top, bot) = palette[colorIndex]

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        circle.colors = [top.cgColor, bot.cgColor]
        CATransaction.commit()

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1.0, 1.25, 0.95, 1.0]
        pop.keyTimes = [0, 0.15, 0.5, 1.0]
        pop.duration = 0.4
        circle.add(pop, forKey: "pop")
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Selection Toolbar
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Minimal floating toolbar that appears when text is selected.
/// Two actions: pin (save directly) and expand (open capture panel).
class SelectionToolbar {
    private var window: NSWindow?
    private var mouseDownPos: NSPoint?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var hideTimer: Timer?

    var onPin: ((String) -> Void)?      // direct save
    var onExpand: ((String, NSPoint) -> Void)?  // open capture panel

    private let toolbarW: CGFloat = 68
    private let toolbarH: CGFloat = 28

    func startMonitoring() {
        // Track mouseDown position to distinguish click vs drag-select
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.mouseDownPos = NSEvent.mouseLocation
            self?.dismiss()
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self else { return }
            let upPos = NSEvent.mouseLocation
            guard let downPos = self.mouseDownPos else { return }

            // Only trigger on drag-select (distance > 20px), not clicks
            let dx = upPos.x - downPos.x
            let dy = upPos.y - downPos.y
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 20 else { return }

            // Wait a moment for the selection to register
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.checkAndShow(at: upPos)
            }
        }
    }

    private func checkAndShow(at pos: NSPoint) {
        // Don't show if capture panel is open
        if let delegate = NSApp.delegate as? AppDelegate,
           delegate.capturePanel?.isOpen == true { return }

        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let pid = frontApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var focused: AnyObject?
        let r1 = AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused)
        guard r1 == .success, let el = focused else { return }

        var sel: AnyObject?
        let r2 = AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel)
        guard r2 == .success, let text = sel as? String else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        show(at: pos, selectedText: trimmed)
    }

    private func show(at mousePos: NSPoint, selectedText: String) {
        dismiss()
        guard let screen = NSScreen.main else { return }

        // Position: slightly below and right of mouse
        var x = mousePos.x + 8
        var y = mousePos.y - toolbarH - 8

        // Keep on screen
        if x + toolbarW > screen.frame.maxX - 10 { x = mousePos.x - toolbarW - 8 }
        if y < screen.frame.minY + 10 { y = mousePos.y + 8 }

        let win = NSWindow(contentRect: NSMakeRect(x, y, toolbarW, toolbarH),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false

        let container = NSView(frame: NSMakeRect(0, 0, toolbarW, toolbarH))
        container.wantsLayer = true
        container.layer?.cornerRadius = toolbarH / 2
        container.layer?.backgroundColor = NSColor(white: 1, alpha: 0.95).cgColor
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.12
        container.layer?.shadowRadius = 10
        container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(white: 0, alpha: 0.06).cgColor

        // Expand button (colored dot — same palette as bubble)
        let dotBtn = ClickableRow(frame: NSMakeRect(4, 4, toolbarH - 8, toolbarH - 8))
        let dotLayer = CAGradientLayer()
        let dotSize = toolbarH - 8
        dotLayer.frame = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dotLayer.cornerRadius = dotSize / 2
        dotLayer.colors = [
            NSColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1).cgColor,
            NSColor(red: 0.38, green: 0.50, blue: 0.85, alpha: 1).cgColor
        ]
        dotLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        dotLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        dotBtn.wantsLayer = true
        dotBtn.layer?.cornerRadius = dotSize / 2
        dotBtn.layer?.addSublayer(dotLayer)
        let text = selectedText
        let pos = mousePos
        dotBtn.onClick = { [weak self] in
            self?.dismiss()
            self?.onExpand?(text, pos)
        }
        container.addSubview(dotBtn)

        // Pin button
        let pinBtn = ClickableRow(frame: NSMakeRect(toolbarW / 2 + 2, 0, toolbarW / 2 - 4, toolbarH))
        let pinLabel = NSTextField(labelWithString: "📌")
        pinLabel.font = NSFont.systemFont(ofSize: 13)
        pinLabel.frame = NSMakeRect((pinBtn.frame.width - 20) / 2, (toolbarH - 18) / 2, 20, 18)
        pinBtn.addSubview(pinLabel)
        pinBtn.onClick = { [weak self] in
            self?.dismiss()
            self?.onPin?(text)
        }
        container.addSubview(pinBtn)

        win.contentView = container

        // Fade in
        container.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            container.animator().alphaValue = 1
        }

        self.window = win

        // Auto-hide after 4 seconds
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func fadeOut() {
        guard let win = window, let content = win.contentView else {
            dismiss()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            content.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Entry Point
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Single-instance guard — exit if another ThoughtCapture is already running
let myPID = ProcessInfo.processInfo.processIdentifier
let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.thoughtcapture.app")
if running.contains(where: { $0.processIdentifier != myPID }) {
    fputs("[TC] Another instance is already running. Exiting.\n", stderr)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
