import Cocoa
import Carbon

let HOTKEY_KEYCODE: UInt32 = 17          // 'T' key
let HOTKEY_SCREENSHOT: UInt32 = 15       // 'R' key
let HOTKEY_MODIFIERS: UInt32 = UInt32(optionKey)  // Option (⌥)

let THOUGHT_COLORS = ["coral", "blue", "purple", "green", "amber", "olive", "pink", "steel"]

struct TC {
    static let green  = NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
    static let red    = NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
    static let primary = NSColor(white: 0.06, alpha: 1)
    static let text    = NSColor(white: 0.13, alpha: 1)
    static let body    = NSColor(white: 0.24, alpha: 1)
    static let sub     = NSColor(white: 0.40, alpha: 1)
    static let muted   = NSColor(white: 0.55, alpha: 1)
    static let faint   = NSColor(white: 0.72, alpha: 1)
    static let rule    = NSColor(white: 0, alpha: 0.07)
    static let ctxBg   = NSColor(white: 0, alpha: 0.035)
}
