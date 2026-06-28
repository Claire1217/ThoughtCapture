import Cocoa

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
    private let aiColor = NSColor(red: 0.55, green: 0.36, blue: 0.85, alpha: 1)
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
                if let tv = self?.textView, tv.hasMarkedText() { return ev }
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
        }
    }

    private func resizeToFit() {
        guard let tv = textView, let sv = scrollView,
              let p = panel, let c = card else { return }

        // Hide/show placeholder
        if let ph = c.viewWithTag(999) {
            ph.isHidden = !tv.string.isEmpty
        }

        // Command mode visual feedback
        let text = tv.string
        let isCmd = text.hasPrefix("/") || text.hasPrefix("／")
                    || text.lowercased().hasPrefix("@claude")
        let isAtClaude = text.lowercased().hasPrefix("@claude")
        if isCmd {
            hintLabel?.stringValue = isAtClaude ? "↵ @claude · esc" : "↵ ask AI · esc"
            hintLabel?.textColor = aiColor
            if !isAIMode {
                isAIMode = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    c.layer?.borderWidth = 1.5
                    c.layer?.borderColor = aiColor.withAlphaComponent(0.35).cgColor
                    c.layer?.shadowColor = aiColor.cgColor
                    c.layer?.shadowOpacity = 0.15
                    c.layer?.shadowRadius = 12
                }
                updatingStyle = true
                let full = NSMutableAttributedString(attributedString: tv.attributedString())
                let range = NSRange(location: 0, length: full.length)
                full.addAttribute(.foregroundColor, value: aiColor, range: range)
                let prefixLen = isAtClaude ? min(7, full.length) : min(1, full.length)
                if prefixLen > 0 {
                    let prefixRange = NSRange(location: 0, length: prefixLen)
                    full.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: prefixRange)
                    full.addAttribute(.kern, value: isAtClaude ? 1 : 3, range: prefixRange)
                }
                tv.textStorage?.setAttributedString(full)
                updatingStyle = false
            }
        } else if isAIMode {
            isAIMode = false
            hintLabel?.stringValue = "\u{21B5} save · esc"
            hintLabel?.textColor = TC.faint
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                c.layer?.borderWidth = 0
                c.layer?.shadowColor = NSColor.black.cgColor
                c.layer?.shadowOpacity = 0.10
                c.layer?.shadowRadius = 16
            }
            updatingStyle = true
            tv.textColor = TC.sub
            updatingStyle = false
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
        let text = typed.isEmpty ? quotedText : typed
        guard !text.isEmpty else { close(); return }
        fputs("[TC] submit: \(text)\n", stderr)
        let isAI = text.hasPrefix("/") || text.hasPrefix("／")
        if !isAI {
            close()
        }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        onSubmit?(text)
    }

    // MARK: Streaming answer display

    private var answerView: NSTextView?
    private var answerScroll: NSScrollView?
    private var answerPhase = false

    func showStreamingAnswer() {
        guard let p = panel, let c = card else { return }
        answerPhase = true

        // Disable input
        textView?.isEditable = false
        textView?.textColor = TC.muted
        hintLabel?.stringValue = "esc 关闭"
        hintLabel?.textColor = TC.faint

        // Prepare answer views (initially hidden, zero height)
        let sep = NSView(frame: NSMakeRect(16, 0, pw - 32, 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.identifier = NSUserInterfaceItemIdentifier("answerSep")
        c.addSubview(sep)

        let asv = NSScrollView(frame: NSMakeRect(10, 8, pw - 20, 0))
        asv.hasVerticalScroller = true
        asv.hasHorizontalScroller = false
        asv.borderType = .noBorder
        asv.drawsBackground = false
        asv.autohidesScrollers = true

        let atv = NSTextView(frame: NSMakeRect(0, 0, pw - 28, 0))
        atv.font = NSFont.systemFont(ofSize: 12)
        atv.textColor = TC.faint
        atv.drawsBackground = false
        atv.isEditable = false
        atv.isSelectable = true
        atv.textContainerInset = NSSize(width: 4, height: 4)
        atv.textContainer?.widthTracksTextView = true
        atv.textContainer?.containerSize = NSSize(width: pw - 36, height: CGFloat.greatestFiniteMagnitude)
        atv.isVerticallyResizable = true
        atv.string = "thinking..."
        asv.documentView = atv
        c.addSubview(asv)
        answerView = atv
        answerScroll = asv

        // Animate expansion
        let ansH: CGFloat = 140
        let frame = p.frame
        let newFrame = NSMakeRect(frame.origin.x, frame.origin.y - ansH,
                                  frame.width, frame.height + ansH)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(newFrame, display: true)
        } completionHandler: {
            c.frame = NSMakeRect(0, 0, newFrame.width, newFrame.height)
            sep.frame = NSMakeRect(16, ansH + 2, self.pw - 32, 1)
            asv.frame = NSMakeRect(10, 8, self.pw - 20, ansH - 12)
            atv.frame = NSMakeRect(0, 0, self.pw - 28, ansH - 12)
        }
    }

    func appendStreamChunk(_ chunk: String) {
        guard let atv = answerView else { return }
        if atv.string == "thinking..." {
            atv.string = ""
            atv.textColor = TC.sub
        }
        atv.string += chunk
        atv.scrollToEndOfDocument(nil)
    }

    func finishStream() {
        hintLabel?.stringValue = "esc 关闭 · 已完成"
        hintLabel?.textColor = TC.faint
    }

    var isOpen: Bool { panel != nil }

    func close() {
        fputs("[TC] CapturePanel.close()\n", stderr)
        answerView = nil; answerScroll = nil; answerPhase = false
        panel?.close(); panel = nil
        screenshotView = nil
        ctxBoxView = nil
        isAIMode = false
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

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

    static func truncate(_ s: String, max: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        if flat.count <= max { return flat }
        let half = (max - 3) / 2
        return "\(flat.prefix(half))...\(flat.suffix(half))"
    }
}
