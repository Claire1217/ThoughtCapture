import Cocoa
import Carbon

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
        dotWin.isMovableByWindowBackground = false
        dotWin.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bubble = ThoughtBubbleView(frame: NSMakeRect(0, 0, dotSize, dotSize))
        bubble.onEnter = { [weak self] in self?.showPopover() }
        bubble.onExit  = { [weak self] in self?.scheduleDismiss() }
        bubble.onLeftClick = { [weak self] in self?.togglePopover() }
        bubble.onSettings = { [weak self] in self?.openSettingsWindow() }
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
        popWin.collectionBehavior = [.canJoinAllSpaces, .stationary]

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

        dotWin.orderFront(nil)
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

    private func togglePopover() {
        if popWin.isVisible {
            dotWin.removeChildWindow(popWin)
            popWin.orderOut(nil)
        } else {
            showPopover()
        }
    }

    // MARK: Settings Window

    private var settingsWin: NSWindow?
    // Keep action targets alive
    private var settingsTargets: [AnyObject] = []

    func openSettingsWindow() {
        if let existing = settingsWin, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsTargets.removeAll()

        let W: CGFloat = 420, H: CGFloat = 500
        let win = NSWindow(contentRect: NSMakeRect(0, 0, W, H),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "ThoughtCapture Settings"
        win.center()
        win.isReleasedWhenClosed = false

        let root = NSView(frame: NSMakeRect(0, 0, W, H))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let px: CGFloat = 24
        let fw: CGFloat = W - px * 2
        var y: CGFloat = H - 24

        // ── Helpers ──
        func sectionTitle(_ text: String, at yy: inout CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 11, weight: .medium)
            l.textColor = .tertiaryLabelColor
            root.addSubview(l)
            l.frame = NSMakeRect(px, yy - 14, fw, 14)
            yy -= 22
        }

        func hint(_ text: String, at yy: inout CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 10)
            l.textColor = .tertiaryLabelColor
            l.frame = NSMakeRect(px, yy - 12, fw, 12)
            root.addSubview(l)
            yy -= 16
        }

        func sep(at yy: inout CGFloat) {
            let s = NSView(frame: NSMakeRect(px, yy - 8, fw, 1))
            s.wantsLayer = true
            s.layer?.backgroundColor = NSColor.separatorColor.cgColor
            root.addSubview(s)
            yy -= 20
        }

        func infoRow(_ label: String, _ value: String, at yy: inout CGFloat) {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = .systemFont(ofSize: 12)
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSMakeRect(px, yy - 16, 100, 16)
            root.addSubview(lbl)
            let val = NSTextField(labelWithString: value)
            val.font = .systemFont(ofSize: 12)
            val.textColor = .labelColor
            val.frame = NSMakeRect(px + 100, yy - 16, fw - 100, 16)
            root.addSubview(val)
            yy -= 22
        }

        // ━━━━━  STORAGE  ━━━━━
        sectionTitle("STORAGE", at: &y)

        let storageSeg = NSSegmentedControl(labels: ["Obsidian Vault", "Apple Notes"], trackingMode: .selectOne, target: nil, action: nil)
        storageSeg.selectedSegment = 0
        storageSeg.frame = NSMakeRect(px, y - 24, fw, 24)
        storageSeg.identifier = NSUserInterfaceItemIdentifier("storage")
        root.addSubview(storageSeg)
        y -= 34

        // Vault folder row
        let vaultRow = NSView(frame: NSMakeRect(px, y - 48, fw, 48))
        vaultRow.identifier = NSUserInterfaceItemIdentifier("vaultRow")
        root.addSubview(vaultRow)

        let vpField = NSTextField(frame: NSMakeRect(0, 26, fw, 22))
        vpField.placeholderString = "e.g. ~/obsidian-vault/01_daily"
        vpField.font = .systemFont(ofSize: 12)
        vpField.identifier = NSUserInterfaceItemIdentifier("vaultPath")
        vpField.bezelStyle = .roundedBezel
        vaultRow.addSubview(vpField)

        let browseBtn = NSButton(title: "Choose…", target: nil, action: nil)
        browseBtn.bezelStyle = .rounded
        browseBtn.controlSize = .small
        browseBtn.font = .systemFont(ofSize: 11)
        browseBtn.frame = NSMakeRect(0, 0, 72, 22)
        vaultRow.addSubview(browseBtn)

        let pathHint = NSTextField(labelWithString: "→ folder / 2026-06-29 / Thoughts.md")
        pathHint.font = .systemFont(ofSize: 10)
        pathHint.textColor = .tertiaryLabelColor
        pathHint.frame = NSMakeRect(78, 3, fw - 78, 14)
        vaultRow.addSubview(pathHint)
        y -= 56

        class BrowseHandler: NSObject {
            weak var pathField: NSTextField?
            @objc func pick(_ sender: Any) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose Vault"
                if panel.runModal() == .OK, let url = panel.url {
                    pathField?.stringValue = url.path
                }
            }
        }
        let browseHandler = BrowseHandler()
        browseHandler.pathField = vpField
        browseBtn.target = browseHandler
        browseBtn.action = #selector(BrowseHandler.pick(_:))
        settingsTargets.append(browseHandler)

        class StorageToggle: NSObject {
            weak var vaultRow: NSView?
            @objc func changed(_ sender: NSSegmentedControl) {
                let isNotes = sender.selectedSegment == 1
                vaultRow?.isHidden = isNotes
                if isNotes {
                    DispatchQueue.global().async {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        proc.arguments = ["-e", "tell application \"Notes\" to get name of first note of default account"]
                        try? proc.run()
                        proc.waitUntilExit()
                    }
                }
            }
        }
        let storageToggle = StorageToggle()
        storageToggle.vaultRow = vaultRow
        storageSeg.target = storageToggle
        storageSeg.action = #selector(StorageToggle.changed(_:))
        settingsTargets.append(storageToggle)

        // ━━━━━  / AI Q&A  ━━━━━
        sep(at: &y)
        sectionTitle("/ AI QUICK ANSWER", at: &y)

        let qaDesc = NSTextField(labelWithString: "Type / then your question to get an AI answer instantly.")
        qaDesc.font = .systemFont(ofSize: 11)
        qaDesc.textColor = .secondaryLabelColor
        qaDesc.frame = NSMakeRect(px, y - 14, fw, 14)
        root.addSubview(qaDesc)
        y -= 22

        let apiLabel = NSTextField(labelWithString: "DeepSeek API Key")
        apiLabel.font = .systemFont(ofSize: 12)
        apiLabel.textColor = .secondaryLabelColor
        apiLabel.frame = NSMakeRect(px, y - 16, fw, 16)
        root.addSubview(apiLabel)
        y -= 22

        let apiKeyField = NSTextField(frame: NSMakeRect(px, y - 22, fw - 72, 22))
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.font = .systemFont(ofSize: 12)
        apiKeyField.identifier = NSUserInterfaceItemIdentifier("llmApiKey")
        apiKeyField.bezelStyle = .roundedBezel
        root.addSubview(apiKeyField)

        let testBtn = NSButton(title: "Test", target: nil, action: nil)
        testBtn.bezelStyle = .rounded
        testBtn.controlSize = .small
        testBtn.font = .systemFont(ofSize: 11)
        testBtn.frame = NSMakeRect(W - px - 62, y - 23, 62, 24)
        root.addSubview(testBtn)

        let testStatus = NSTextField(labelWithString: "")
        testStatus.font = .systemFont(ofSize: 11)
        testStatus.frame = NSMakeRect(px, y - 38, fw, 14)
        testStatus.identifier = NSUserInterfaceItemIdentifier("testStatus")
        root.addSubview(testStatus)

        class TestHandler: NSObject {
            weak var keyField: NSTextField?
            weak var statusLabel: NSTextField?
            @objc func test(_ sender: Any) {
                let key = keyField?.stringValue ?? ""
                guard !key.isEmpty else {
                    statusLabel?.textColor = .systemOrange
                    statusLabel?.stringValue = "Please enter an API key first"
                    return
                }
                statusLabel?.textColor = .secondaryLabelColor
                statusLabel?.stringValue = "Testing…"

                let base = LocalStorage.shared.llmApiBase
                let url = URL(string: "\(base)/chat/completions")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "model": LocalStorage.shared.llmModel,
                    "messages": [["role": "user", "content": "hi"]],
                    "max_tokens": 1
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                let label = self.statusLabel
                URLSession.shared.dataTask(with: req) { _, resp, err in
                    DispatchQueue.main.async {
                        if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                            label?.textColor = .systemGreen
                            label?.stringValue = "✓ Connected"
                        } else {
                            label?.textColor = .systemRed
                            label?.stringValue = "✗ Failed — check your key"
                        }
                    }
                }.resume()
            }
        }
        let testHandler = TestHandler()
        testHandler.keyField = apiKeyField
        testHandler.statusLabel = testStatus
        testBtn.target = testHandler
        testBtn.action = #selector(TestHandler.test(_:))
        settingsTargets.append(testHandler)
        y -= 42

        // ━━━━━  HOTKEYS  ━━━━━
        sep(at: &y)
        sectionTitle("HOTKEYS", at: &y)

        let modLabels = ["⌥ Option", "⌘ Command", "⌃ Control", "⇧ Shift"]
        let modValues: [UInt32] = [UInt32(optionKey), UInt32(cmdKey), UInt32(controlKey), UInt32(shiftKey)]
        let keyLabels = ["A","B","C","D","E","F","G","H","I","J","K","L","M",
                         "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        let keyCodes: [String: UInt32] = [
            "A":0,"B":11,"C":8,"D":2,"E":14,"F":3,"G":5,"H":4,"I":34,"J":38,
            "K":40,"L":37,"M":46,"N":45,"O":31,"P":35,"Q":12,"R":15,"S":1,
            "T":17,"U":32,"V":9,"W":13,"X":7,"Y":16,"Z":6
        ]
        func keyForCode(_ code: UInt32) -> String {
            keyCodes.first(where: { $0.value == code })?.key ?? "T"
        }
        func modIndex(_ mods: UInt32) -> Int {
            modValues.firstIndex(of: mods) ?? 0
        }

        let curCapKey = UserDefaults.standard.object(forKey: "hotkeyCapture") as? UInt32 ?? 17
        let curCapMod = UserDefaults.standard.object(forKey: "hotkeyCaptureMods") as? UInt32 ?? UInt32(optionKey)
        let curSSKey = UserDefaults.standard.object(forKey: "hotkeyScreenshot") as? UInt32 ?? 15
        let curSSMod = UserDefaults.standard.object(forKey: "hotkeyScreenshotMods") as? UInt32 ?? UInt32(optionKey)

        let labelW: CGFloat = 80
        let popModW: CGFloat = 120
        let popKeyW: CGFloat = 56
        let popX = px + labelW
        let plusX = popX + popModW + 4
        let keyX = plusX + 16

        // Capture row
        let capLabel = NSTextField(labelWithString: "Capture:")
        capLabel.font = .systemFont(ofSize: 12)
        capLabel.textColor = .secondaryLabelColor
        capLabel.frame = NSMakeRect(px, y - 20, labelW, 16)
        root.addSubview(capLabel)

        let capModPop = NSPopUpButton(frame: NSMakeRect(popX, y - 24, popModW, 24))
        capModPop.addItems(withTitles: modLabels)
        capModPop.selectItem(at: modIndex(curCapMod))
        capModPop.font = .systemFont(ofSize: 12)
        capModPop.identifier = NSUserInterfaceItemIdentifier("capMod")
        root.addSubview(capModPop)

        let plusLabel1 = NSTextField(labelWithString: "+")
        plusLabel1.font = .systemFont(ofSize: 13, weight: .medium)
        plusLabel1.textColor = .secondaryLabelColor
        plusLabel1.frame = NSMakeRect(plusX, y - 20, 14, 16)
        root.addSubview(plusLabel1)

        let capKeyPop = NSPopUpButton(frame: NSMakeRect(keyX, y - 24, popKeyW, 24))
        capKeyPop.addItems(withTitles: keyLabels)
        capKeyPop.selectItem(withTitle: keyForCode(curCapKey))
        capKeyPop.font = .systemFont(ofSize: 12)
        capKeyPop.identifier = NSUserInterfaceItemIdentifier("capKey")
        root.addSubview(capKeyPop)
        y -= 30

        // Screenshot row
        let ssLabel = NSTextField(labelWithString: "Screenshot:")
        ssLabel.font = .systemFont(ofSize: 12)
        ssLabel.textColor = .secondaryLabelColor
        ssLabel.frame = NSMakeRect(px, y - 20, labelW, 16)
        root.addSubview(ssLabel)

        let ssModPop = NSPopUpButton(frame: NSMakeRect(popX, y - 24, popModW, 24))
        ssModPop.addItems(withTitles: modLabels)
        ssModPop.selectItem(at: modIndex(curSSMod))
        ssModPop.font = .systemFont(ofSize: 12)
        ssModPop.identifier = NSUserInterfaceItemIdentifier("ssMod")
        root.addSubview(ssModPop)

        let plusLabel2 = NSTextField(labelWithString: "+")
        plusLabel2.font = .systemFont(ofSize: 13, weight: .medium)
        plusLabel2.textColor = .secondaryLabelColor
        plusLabel2.frame = NSMakeRect(plusX, y - 20, 14, 16)
        root.addSubview(plusLabel2)

        let ssKeyPop = NSPopUpButton(frame: NSMakeRect(keyX, y - 24, popKeyW, 24))
        ssKeyPop.addItems(withTitles: keyLabels)
        ssKeyPop.selectItem(withTitle: keyForCode(curSSKey))
        ssKeyPop.font = .systemFont(ofSize: 12)
        ssKeyPop.identifier = NSUserInterfaceItemIdentifier("ssKey")
        root.addSubview(ssKeyPop)
        y -= 30

        // ━━━━━  ABOUT  ━━━━━
        sep(at: &y)
        sectionTitle("ABOUT", at: &y)

        infoRow("Version:", "1.0", at: &y)

        // ━━━━━  Bottom bar  ━━━━━
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemGreen
        statusLabel.frame = NSMakeRect(px, 17, 200, 14)
        statusLabel.identifier = NSUserInterfaceItemIdentifier("status")
        root.addSubview(statusLabel)

        let saveBtn = NSButton(title: "Save", target: nil, action: nil)
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSMakeRect(W - px - 70, 12, 70, 26)
        saveBtn.keyEquivalent = "\r"
        root.addSubview(saveBtn)

        win.contentView = root

        // ── Save handler ──
        class SaveHandler: NSObject {
            weak var root: NSView?
            @objc func save(_ sender: Any) {
                guard let root = root else { return }

                func textField(in view: NSView, id: String) -> NSTextField? {
                    for sub in view.subviews {
                        if let tf = sub as? NSTextField, tf.identifier?.rawValue == id { return tf }
                        if let found = textField(in: sub, id: id) { return found }
                    }
                    return nil
                }
                func segValue(in view: NSView, id: String) -> Int {
                    for sub in view.subviews {
                        if let seg = sub as? NSSegmentedControl, seg.identifier?.rawValue == id { return seg.selectedSegment }
                        let found = segValue(in: sub, id: id)
                        if found >= 0 { return found }
                    }
                    return -1
                }

                let isObsidian = segValue(in: root, id: "storage") == 0
                let vaultPath = textField(in: root, id: "vaultPath")?.stringValue ?? ""
                let backend = isObsidian ? "obsidian" : "notes"
                let apiKey = textField(in: root, id: "llmApiKey")?.stringValue ?? ""

                LocalStorage.shared.vaultPath = vaultPath
                LocalStorage.shared.backend = backend
                if !apiKey.isEmpty {
                    LocalStorage.shared.llmApiKey = apiKey
                }
                // Find vault root by walking up to the folder containing .obsidian/
                let expanded = NSString(string: vaultPath).expandingTildeInPath
                var dir = expanded
                var foundVault = ""
                while dir != "/" && !dir.isEmpty {
                    if FileManager.default.fileExists(atPath: "\(dir)/.obsidian") {
                        foundVault = URL(fileURLWithPath: dir).lastPathComponent
                        break
                    }
                    dir = (dir as NSString).deletingLastPathComponent
                }
                if !foundVault.isEmpty {
                    ResultBubble.vaultName = foundVault
                    UserDefaults.standard.set(foundVault, forKey: "vaultName")
                }
                if isObsidian { LocalStorage.shared.installObsidianSnippet() }

                // Save hotkeys from dropdowns
                let modVals: [UInt32] = [UInt32(optionKey), UInt32(cmdKey), UInt32(controlKey), UInt32(shiftKey)]
                let keyMap: [String: UInt32] = [
                    "A":0,"B":11,"C":8,"D":2,"E":14,"F":3,"G":5,"H":4,"I":34,"J":38,
                    "K":40,"L":37,"M":46,"N":45,"O":31,"P":35,"Q":12,"R":15,"S":1,
                    "T":17,"U":32,"V":9,"W":13,"X":7,"Y":16,"Z":6
                ]
                func popupIndex(in view: NSView, id: String) -> Int {
                    for sub in view.subviews {
                        if let pop = sub as? NSPopUpButton, pop.identifier?.rawValue == id {
                            return pop.indexOfSelectedItem
                        }
                        let found = popupIndex(in: sub, id: id)
                        if found >= 0 { return found }
                    }
                    return -1
                }
                func popupTitle(in view: NSView, id: String) -> String? {
                    for sub in view.subviews {
                        if let pop = sub as? NSPopUpButton, pop.identifier?.rawValue == id {
                            return pop.titleOfSelectedItem
                        }
                        if let found = popupTitle(in: sub, id: id) { return found }
                    }
                    return nil
                }

                let capModIdx = popupIndex(in: root, id: "capMod")
                if capModIdx >= 0 { UserDefaults.standard.set(modVals[capModIdx], forKey: "hotkeyCaptureMods") }
                if let k = popupTitle(in: root, id: "capKey"), let code = keyMap[k] {
                    UserDefaults.standard.set(code, forKey: "hotkeyCapture")
                }
                let ssModIdx = popupIndex(in: root, id: "ssMod")
                if ssModIdx >= 0 { UserDefaults.standard.set(modVals[ssModIdx], forKey: "hotkeyScreenshotMods") }
                if let k = popupTitle(in: root, id: "ssKey"), let code = keyMap[k] {
                    UserDefaults.standard.set(code, forKey: "hotkeyScreenshot")
                }
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.registerHotkey()
                }

                let status = textField(in: root, id: "status")
                status?.textColor = .systemGreen
                status?.stringValue = "✓ Saved"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    status?.stringValue = ""
                }
            }
        }
        let saveHandler = SaveHandler()
        saveHandler.root = root
        saveBtn.target = saveHandler
        saveBtn.action = #selector(SaveHandler.save(_:))
        settingsTargets.append(saveHandler)

        // ── Load current values ──
        loadSettings(root: root, storageSeg: storageSeg, vaultRow: vaultRow)

        settingsWin = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadSettings(root: NSView, storageSeg: NSSegmentedControl, vaultRow: NSView) {
        func textField(in view: NSView, id: String) -> NSTextField? {
            for sub in view.subviews {
                if let tf = sub as? NSTextField, tf.identifier?.rawValue == id { return tf }
                if let found = textField(in: sub, id: id) { return found }
            }
            return nil
        }
        let storage = LocalStorage.shared.backend
        storageSeg.selectedSegment = storage == "notes" ? 1 : 0
        vaultRow.isHidden = storage == "notes"

        let savedVaultPath = LocalStorage.shared.vaultPath
        if !savedVaultPath.isEmpty {
            textField(in: root, id: "vaultPath")?.stringValue = savedVaultPath
        }
        let savedKey = LocalStorage.shared.llmApiKey
        if !savedKey.isEmpty {
            textField(in: root, id: "llmApiKey")?.stringValue = savedKey
        }
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

    private func rebuildPopover() {
        guard let container = popWin.contentView as? TrackView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let rowH: CGFloat = 32
        let pad: CGFloat = 8

        let visibleThoughts = items
        let thoughtCount = min(visibleThoughts.count, 8)

        // Empty state
        if thoughtCount == 0 {
            let emptyH: CGFloat = 64
            container.frame = NSMakeRect(0, 0, popWidth, emptyH)
            let hint = NSTextField(labelWithString: "Press \(captureHotkeyLabel) to capture a thought")
            hint.font = rounded(size: 12)
            hint.textColor = TC.muted
            hint.alignment = .center
            hint.frame = NSMakeRect(10, (emptyH - 16) / 2, popWidth - 20, 16)
            container.addSubview(hint)
            popWin.setContentSize(NSSize(width: popWidth, height: emptyH))
            return
        }

        // Calculate total height
        var totalH = pad
        totalH += 18
        totalH += CGFloat(thoughtCount) * rowH
        totalH += 8

        container.frame = NSMakeRect(0, 0, popWidth, totalH)
        var y = totalH - pad

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
                row.onClick = { ResultBubble.openSavedThought(path: path, searchText: text) }
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

    // MARK: Open in Obsidian

    static var vaultName: String = {
        if let name = UserDefaults.standard.string(forKey: "vaultName"), !name.isEmpty {
            return name
        }
        let vaultPath = LocalStorage.shared.vaultPath
        if !vaultPath.isEmpty {
            return URL(fileURLWithPath: vaultPath).lastPathComponent
        }
        return "obsidian"
    }()

    static var storageBackend: String = {
        UserDefaults.standard.string(forKey: "storageBackend") ?? "obsidian"
    }()

    static func fetchConfig(sync: Bool = false) {
        if let name = UserDefaults.standard.string(forKey: "vaultName"), !name.isEmpty {
            vaultName = name
        }
        if let backend = UserDefaults.standard.string(forKey: "storageBackend"), !backend.isEmpty {
            storageBackend = backend
        }
    }

    /// Open a saved thought — dispatches to Obsidian or Apple Notes based on backend.
    static func openSavedThought(path: String, searchText: String = "") {
        if storageBackend == "notes" {
            openInNotes(searchText: searchText)
        } else {
            openInObsidian(path: path, searchText: searchText)
        }
    }

    static func openInObsidian(path: String, searchText: String = "") {
        guard !path.isEmpty else { return }
        let file = path.components(separatedBy: " + ").first ?? path
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file
        if let url = URL(string: "obsidian://open?vault=\(vaultName)&file=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        if !searchText.isEmpty {
            let query = String(searchText.prefix(30))
            let searchQuery = "path:\"\(file)\" \"\(query)\""
            if let sq = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let searchUrl = URL(string: "obsidian://search?vault=\(vaultName)&query=\(sq)") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSWorkspace.shared.open(searchUrl)
                }
            }
        }
    }

    static func openInNotes(searchText: String = "") {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: Date())
        let noteTitle = "Thoughts — \(dateStr)"
        let script = """
        tell application "Notes"
            activate
            set noteFound to false
            repeat with n in notes of default account
                if name of n is "\(noteTitle)" then
                    show n
                    set noteFound to true
                    exit repeat
                end if
            end repeat
        end tell
        """
        DispatchQueue.global().async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
        }
    }
}
