import Cocoa

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
    var onLeftClick: (() -> Void)?
    var onSettings: (() -> Void)?
    private var dragOrigin: NSPoint?
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let loc = event.locationInWindow
        let dx = abs(loc.x - origin.x), dy = abs(loc.y - origin.y)
        if dx > 3 || dy > 3 { isDragging = true }
        if isDragging, let win = window {
            var frame = win.frame
            frame.origin.x += event.deltaX
            frame.origin.y -= event.deltaY
            win.setFrameOrigin(frame.origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging { onLeftClick?() }
        dragOrigin = nil
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…",
                                       action: #selector(openSettings),
                                       keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ThoughtCapture",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func openSettings() { onSettings?() }

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

    override var mouseDownCanMoveWindow: Bool { false }

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
