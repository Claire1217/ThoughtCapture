import Cocoa
import Carbon

// MARK: - Hotkey Recorder

class HotkeyRecorder: NSView {
    let defaultsKey: String
    var keyCode: UInt32
    var modifiers: UInt32
    private var recording = false
    private var label: NSTextField!
    private var monitor: Any?

    private static let codeToName: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
        11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",
        20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",
        29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
        47:".",44:"/",49:"Space",36:"Return",48:"Tab",51:"Delete",53:"Esc",
        122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",
        100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"
    ]

    init(defaultsKey: String, defaultCode: UInt32, defaultMods: UInt32) {
        self.defaultsKey = defaultsKey
        self.keyCode = UserDefaults.standard.object(forKey: defaultsKey) as? UInt32 ?? defaultCode
        self.modifiers = UserDefaults.standard.object(forKey: defaultsKey + "Mods") as? UInt32 ?? defaultMods
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label = NSTextField(labelWithString: displayString())
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func displayString() -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.codeToName[keyCode] ?? "?")
        return parts.joined()
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    private func startRecording() {
        recording = true
        label.stringValue = "Press shortcut…"
        label.textColor = .systemOrange
        layer?.borderColor = NSColor.systemOrange.cgColor

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if recording { handleKey(event) }
    }

    private func handleKey(_ event: NSEvent) {
        guard recording else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Need at least one modifier
        guard flags.contains(.option) || flags.contains(.command) ||
              flags.contains(.control) || flags.contains(.shift) else { return }

        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }

        keyCode = UInt32(event.keyCode)
        modifiers = mods
        stopRecording()
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        label.stringValue = displayString()
        label.textColor = .labelColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func save() {
        UserDefaults.standard.set(keyCode, forKey: defaultsKey)
        UserDefaults.standard.set(modifiers, forKey: defaultsKey + "Mods")
    }
}

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

        let W: CGFloat = 400, H: CGFloat = 480
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
        let vaultRow = NSView(frame: NSMakeRect(px, y - 26, fw, 26))
        vaultRow.identifier = NSUserInterfaceItemIdentifier("vaultRow")
        root.addSubview(vaultRow)

        let vpField = NSTextField(frame: NSMakeRect(0, 2, fw - 66, 22))
        vpField.placeholderString = "Choose your Obsidian vault folder…"
        vpField.font = .systemFont(ofSize: 12)
        vpField.identifier = NSUserInterfaceItemIdentifier("vaultPath")
        vpField.bezelStyle = .roundedBezel
        vaultRow.addSubview(vpField)

        let browseBtn = NSButton(title: "Choose…", target: nil, action: nil)
        browseBtn.bezelStyle = .rounded
        browseBtn.controlSize = .small
        browseBtn.font = .systemFont(ofSize: 11)
        browseBtn.frame = NSMakeRect(fw - 62, 1, 62, 22)
        vaultRow.addSubview(browseBtn)
        y -= 34

        // Note path template
        let notePathRow = NSView(frame: NSMakeRect(px, y - 26, fw, 26))
        notePathRow.identifier = NSUserInterfaceItemIdentifier("notePathRow")
        root.addSubview(notePathRow)

        let npLabel = NSTextField(labelWithString: "Save to:")
        npLabel.font = .systemFont(ofSize: 12)
        npLabel.textColor = .secondaryLabelColor
        npLabel.frame = NSMakeRect(0, 4, 52, 16)
        notePathRow.addSubview(npLabel)

        let npField = NSTextField(frame: NSMakeRect(54, 2, fw - 54, 22))
        npField.placeholderString = "01_daily/{date}/Daily random thoughts.md"
        npField.font = .systemFont(ofSize: 11)
        npField.identifier = NSUserInterfaceItemIdentifier("notePath")
        npField.bezelStyle = .roundedBezel
        notePathRow.addSubview(npField)
        y -= 30

        hint("{date} = 2026-06-29", at: &y)

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
            weak var notePathRow: NSView?
            @objc func changed(_ sender: NSSegmentedControl) {
                let isNotes = sender.selectedSegment == 1
                vaultRow?.isHidden = isNotes
                notePathRow?.isHidden = isNotes
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
        storageToggle.notePathRow = notePathRow
        storageSeg.target = storageToggle
        storageSeg.action = #selector(StorageToggle.changed(_:))
        settingsTargets.append(storageToggle)

        // ━━━━━  QUICK Q&A  ━━━━━
        sep(at: &y)
        sectionTitle("QUICK Q&A", at: &y)

        // Status indicator
        let hasKey = !LocalStorage.shared.llmApiKey.isEmpty
        let statusDot = NSTextField(labelWithString: hasKey ? "✓ Connected" : "✗ Not configured")
        statusDot.font = .systemFont(ofSize: 12)
        statusDot.textColor = hasKey ? .systemGreen : .systemOrange
        statusDot.frame = NSMakeRect(px, y - 16, fw - 80, 16)
        statusDot.identifier = NSUserInterfaceItemIdentifier("apiStatus")
        root.addSubview(statusDot)

        let modelLabel = NSTextField(labelWithString: LocalStorage.shared.llmModel)
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .tertiaryLabelColor
        modelLabel.alignment = .right
        modelLabel.frame = NSMakeRect(W - px - 80, y - 16, 80, 16)
        root.addSubview(modelLabel)
        y -= 26

        let apiKeyField = NSSecureTextField(frame: NSMakeRect(px, y - 22, fw, 22))
        apiKeyField.placeholderString = "sk-..."
        apiKeyField.font = .systemFont(ofSize: 12)
        apiKeyField.identifier = NSUserInterfaceItemIdentifier("llmApiKey")
        apiKeyField.bezelStyle = .roundedBezel
        root.addSubview(apiKeyField)
        y -= 28

        hint("Type / to ask AI · Get key: platform.deepseek.com", at: &y)

        // ━━━━━  HOTKEYS  ━━━━━
        sep(at: &y)
        sectionTitle("HOTKEYS", at: &y)

        let capLabel = NSTextField(labelWithString: "Capture:")
        capLabel.font = .systemFont(ofSize: 12)
        capLabel.textColor = .secondaryLabelColor
        capLabel.frame = NSMakeRect(px, y - 22, 80, 20)
        root.addSubview(capLabel)

        let capRecorder = HotkeyRecorder(defaultsKey: "hotkeyCapture", defaultCode: 17, defaultMods: UInt32(optionKey))
        capRecorder.frame = NSMakeRect(px + 82, y - 24, 120, 24)
        root.addSubview(capRecorder)
        settingsTargets.append(capRecorder)

        let ssLabel = NSTextField(labelWithString: "Screenshot:")
        ssLabel.font = .systemFont(ofSize: 12)
        ssLabel.textColor = .secondaryLabelColor
        ssLabel.frame = NSMakeRect(px + 220, y - 22, 80, 20)
        root.addSubview(ssLabel)

        let ssRecorder = HotkeyRecorder(defaultsKey: "hotkeyScreenshot", defaultCode: 15, defaultMods: UInt32(optionKey))
        ssRecorder.frame = NSMakeRect(px + 302, y - 24, 120, 24)
        root.addSubview(ssRecorder)
        settingsTargets.append(ssRecorder)
        y -= 32

        hint("Click to record, then press your shortcut", at: &y)

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
                let vaultName = URL(fileURLWithPath: vaultPath).lastPathComponent
                let backend = isObsidian ? "obsidian" : "notes"
                let apiKey = textField(in: root, id: "llmApiKey")?.stringValue ?? ""
                let notePath = textField(in: root, id: "notePath")?.stringValue ?? ""

                LocalStorage.shared.vaultPath = vaultPath
                LocalStorage.shared.backend = backend
                if !apiKey.isEmpty {
                    LocalStorage.shared.llmApiKey = apiKey
                }
                if !notePath.isEmpty {
                    UserDefaults.standard.set(notePath, forKey: "notePath")
                }
                if !vaultName.isEmpty {
                    ResultBubble.vaultName = vaultName
                    UserDefaults.standard.set(vaultName, forKey: "vaultName")
                }

                // Save hotkeys from recorders
                func findRecorders(in view: NSView) -> [HotkeyRecorder] {
                    var result: [HotkeyRecorder] = []
                    for sub in view.subviews {
                        if let r = sub as? HotkeyRecorder { result.append(r) }
                        result.append(contentsOf: findRecorders(in: sub))
                    }
                    return result
                }
                for recorder in findRecorders(in: root) { recorder.save() }
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.registerHotkey()
                }

                // Update status indicator
                let statusField = textField(in: root, id: "apiStatus")
                let keySet = !LocalStorage.shared.llmApiKey.isEmpty
                statusField?.stringValue = keySet ? "✓ Connected" : "✗ Not configured"
                statusField?.textColor = keySet ? .systemGreen : .systemOrange

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
        loadSettings(root: root, storageSeg: storageSeg, vaultRow: vaultRow, notePathRow: notePathRow)

        settingsWin = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadSettings(root: NSView, storageSeg: NSSegmentedControl,
                              vaultRow: NSView, notePathRow: NSView) {
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
        notePathRow.isHidden = storage == "notes"

        let savedVaultPath = LocalStorage.shared.vaultPath
        if !savedVaultPath.isEmpty {
            textField(in: root, id: "vaultPath")?.stringValue = savedVaultPath
        }
        let savedKey = LocalStorage.shared.llmApiKey
        if !savedKey.isEmpty {
            textField(in: root, id: "llmApiKey")?.stringValue = savedKey
        }
        let savedNotePath = UserDefaults.standard.string(forKey: "notePath") ?? ""
        if !savedNotePath.isEmpty {
            textField(in: root, id: "notePath")?.stringValue = savedNotePath
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
            let hint = NSTextField(labelWithString: "Press ⌥T to capture a thought")
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
