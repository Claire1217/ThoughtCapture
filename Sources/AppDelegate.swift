import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var hotKeyScreenshotRef: EventHotKeyRef?
    var capturePanel: CapturePanel?
    var resultBubble: ResultBubble?
    var selectionToolbar: SelectionToolbar?
    var prevAppBundleId: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        fputs("[TC] AX trusted on launch: \(trusted)\n", stderr)

        setupMenubar()
        registerHotkey()
        resultBubble = ResultBubble()
        ResultBubble.fetchConfig(sync: true)
        setupSelectionToolbar()

        if LocalStorage.shared.vaultPath.isEmpty && LocalStorage.shared.backend == "obsidian" {
            showFirstLaunchSetup()
        }
    }

    func showFirstLaunchSetup() {
        let alert = NSAlert()
        alert.messageText = "Welcome to ThoughtCapture"
        alert.informativeText = "Press \(captureHotkeyLabel) anywhere to capture a thought.\n\nFirst, choose where to save your thoughts:"
        alert.addButton(withTitle: "Choose Obsidian Vault…")
        alert.addButton(withTitle: "Use Apple Notes")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.prompt = "Select Vault"
            panel.message = "Choose your Obsidian vault folder"
            if panel.runModal() == .OK, let url = panel.url {
                LocalStorage.shared.vaultPath = url.path
                LocalStorage.shared.backend = "obsidian"
                // Walk up to find vault root (.obsidian/ directory)
                var dir = url.path
                while dir != "/" && !dir.isEmpty {
                    if FileManager.default.fileExists(atPath: "\(dir)/.obsidian") {
                        let name = URL(fileURLWithPath: dir).lastPathComponent
                        ResultBubble.vaultName = name
                        UserDefaults.standard.set(name, forKey: "vaultName")
                        break
                    }
                    dir = (dir as NSString).deletingLastPathComponent
                }
            }
        } else {
            LocalStorage.shared.backend = "notes"
        }
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
        let captureItem = NSMenuItem(title: "Capture Thought (\(captureHotkeyLabel))",
                                     action: #selector(triggerCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        let screenshotItem = NSMenuItem(title: "Screenshot + Comment (⌥R)",
                                        action: #selector(triggerScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: Global Hotkey (Carbon)

    private var eventHandlerInstalled = false

    func registerHotkey() {
        // Unregister old hotkeys if re-registering
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = hotKeyScreenshotRef { UnregisterEventHotKey(ref); hotKeyScreenshotRef = nil }

        if !eventHandlerInstalled {
            var eventType = EventTypeSpec()
            eventType.eventClass = OSType(kEventClassKeyboard)
            eventType.eventKind = UInt32(kEventHotKeyPressed)
            InstallEventHandler(
                GetApplicationEventTarget(), hotKeyHandler, 1, &eventType,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), nil)
            eventHandlerInstalled = true
        }

        let captureKey = UserDefaults.standard.object(forKey: "hotkeyCapture") as? UInt32 ?? HOTKEY_KEYCODE
        let captureMods = UserDefaults.standard.object(forKey: "hotkeyCaptureMods") as? UInt32 ?? HOTKEY_MODIFIERS
        let screenshotKey = UserDefaults.standard.object(forKey: "hotkeyScreenshot") as? UInt32 ?? HOTKEY_SCREENSHOT
        let screenshotMods = UserDefaults.standard.object(forKey: "hotkeyScreenshotMods") as? UInt32 ?? HOTKEY_MODIFIERS

        var hotKeyID1 = EventHotKeyID()
        hotKeyID1.signature = OSType(0x54435F48)
        hotKeyID1.id = 1
        RegisterEventHotKey(captureKey, captureMods, hotKeyID1,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        var hotKeyID2 = EventHotKeyID()
        hotKeyID2.signature = OSType(0x54435F48)
        hotKeyID2.id = 2
        RegisterEventHotKey(screenshotKey, screenshotMods, hotKeyID2,
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

    // MARK: Save Thought

    func sendToServer(thought: String, selectedText: String,
                      appName: String, windowTitle: String, browserURL: String,
                      editable: Bool = false, screenshotPath: String? = nil) {
        let cleanThought = thought

        // Any "/" prefix → DeepSeek quick Q&A (streaming in panel)
        if cleanThought.hasPrefix("/") || cleanThought.hasPrefix("／") {
            let stripped = String(cleanThought.drop(while: { $0 == "/" || $0 == "／" }))
            // Also strip known prefixes like 问/ask
            var question = stripped
            for p in ["问", "ask"] {
                if question.hasPrefix(p) {
                    question = String(question.dropFirst(p.count))
                    break
                }
            }
            question = question.trimmingCharacters(in: .whitespaces)
            if question.isEmpty { return }
            capturePanel?.showStreamingAnswer()
            askDeepSeekStreaming(question: question, context: selectedText)
            return
        }
        if cleanThought.isEmpty && selectedText.isEmpty { return }

        let result = LocalStorage.shared.save(
            thought: cleanThought, selectedText: selectedText,
            appName: appName, browserURL: browserURL,
            screenshotPath: screenshotPath)


        capturePanel?.close()
        resultBubble?.addItem(text: cleanThought, savedTo: result.savedTo, ok: result.ok)
    }

    private var streamSession: URLSession?
    private var streamDelegate: StreamingDelegate?

    func askDeepSeekStreaming(question: String, context: String) {
        let storage = LocalStorage.shared
        let apiKey = storage.llmApiKey
        let apiBase = storage.llmApiBase
        let model = storage.llmModel

        guard !apiKey.isEmpty else {
            fputs("[TC] DeepSeek API key not set\n", stderr)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.capturePanel?.finishStreamWithMessage("API key 未设置\n\n右键菜单栏 TC → Settings → 填入 DeepSeek API key\n获取: platform.deepseek.com")
            }
            return
        }

        var messages: [[String: String]] = [
            ["role": "system", "content": "你是一个简洁的助手。用中英混合回答，技术术语用英文。回答控制在200字以内。"]
        ]
        if !context.isEmpty {
            messages.append(["role": "user", "content": "参考内容：\n\(context)\n\n问题：\(question)"])
        } else {
            messages.append(["role": "user", "content": question])
        }

        let body: [String: Any] = ["model": model, "messages": messages,
                                    "max_tokens": 512, "temperature": 0.7, "stream": true]

        guard let url = URL(string: apiBase),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = jsonData
        req.timeoutInterval = 60

        let del = StreamingDelegate(panel: capturePanel, bubble: resultBubble, question: question)
        streamDelegate = del
        let session = URLSession(configuration: .default, delegate: del, delegateQueue: nil)
        streamSession = session
        session.dataTask(with: req).resume()
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

// MARK: - SSE Streaming Delegate

class StreamingDelegate: NSObject, URLSessionDataDelegate {
    weak var panel: CapturePanel?
    weak var bubble: ResultBubble?
    let question: String
    private var buffer = ""
    private var fullAnswer = ""

    init(panel: CapturePanel?, bubble: ResultBubble?, question: String) {
        self.panel = panel
        self.bubble = bubble
        self.question = question
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.panel?.finishStream()
                    fputs("[TC] DeepSeek stream done: \(self.fullAnswer.prefix(80))...\n", stderr)
                }
                return
            }

            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }

            fullAnswer += content
            DispatchQueue.main.async { [weak self] in
                self?.panel?.appendStreamChunk(content)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let err = error {
            DispatchQueue.main.async { [weak self] in
                fputs("[TC] DeepSeek stream error: \(err.localizedDescription)\n", stderr)
                self?.panel?.appendStreamChunk("\n⚠️ \(err.localizedDescription)")
                self?.panel?.finishStream()
            }
        }
    }
}
