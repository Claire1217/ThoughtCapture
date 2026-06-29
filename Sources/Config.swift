import Cocoa
import Carbon

let HOTKEY_KEYCODE: UInt32 = 17          // 'T' key
let HOTKEY_SCREENSHOT: UInt32 = 15       // 'R' key
let HOTKEY_MODIFIERS: UInt32 = UInt32(optionKey)  // Option (⌥)

private let keyCodeNames: [UInt32: String] = [
    0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
    11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",32:"U",34:"I",
    35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",31:"O"
]

func hotkeyLabel(_ keyDefault: String, _ modDefault: String, fallbackKey: UInt32, fallbackMod: UInt32) -> String {
    let code = UserDefaults.standard.object(forKey: keyDefault) as? UInt32 ?? fallbackKey
    let mods = UserDefaults.standard.object(forKey: modDefault) as? UInt32 ?? fallbackMod
    var sym = ""
    if mods & UInt32(controlKey) != 0 { sym += "⌃" }
    if mods & UInt32(optionKey) != 0 { sym += "⌥" }
    if mods & UInt32(shiftKey) != 0 { sym += "⇧" }
    if mods & UInt32(cmdKey) != 0 { sym += "⌘" }
    sym += keyCodeNames[code] ?? "?"
    return sym
}

var captureHotkeyLabel: String {
    hotkeyLabel("hotkeyCapture", "hotkeyCaptureMods", fallbackKey: HOTKEY_KEYCODE, fallbackMod: HOTKEY_MODIFIERS)
}

var screenshotHotkeyLabel: String {
    hotkeyLabel("hotkeyScreenshot", "hotkeyScreenshotMods", fallbackKey: HOTKEY_SCREENSHOT, fallbackMod: HOTKEY_MODIFIERS)
}

let THOUGHT_COLORS = ["coral", "blue", "purple", "green", "amber", "olive", "pink", "steel"]

struct EU {
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
