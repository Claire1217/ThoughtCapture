import Cocoa

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
