import Cocoa

class LocalStorage {
    static let shared = LocalStorage()
    private var colorIndex = 0

    var claudeBin: String {
        if let custom = UserDefaults.standard.string(forKey: "claudeBin"), !custom.isEmpty {
            return custom
        }
        let candidates = [
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    var vaultPath: String {
        get { UserDefaults.standard.string(forKey: "vaultPath") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "vaultPath") }
    }

    var backend: String {
        get { UserDefaults.standard.string(forKey: "storageBackend") ?? "obsidian" }
        set {
            UserDefaults.standard.set(newValue, forKey: "storageBackend")
            ResultBubble.storageBackend = newValue
        }
    }

    var thoughtAgentMode: String {
        get { UserDefaults.standard.string(forKey: "thoughtAgentMode") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "thoughtAgentMode") }
    }

    var llmApiKey: String {
        get { UserDefaults.standard.string(forKey: "llmApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "llmApiKey") }
    }

    var llmApiBase: String {
        get { UserDefaults.standard.string(forKey: "llmApiBase") ?? "https://api.deepseek.com/chat/completions" }
        set { UserDefaults.standard.set(newValue, forKey: "llmApiBase") }
    }

    var llmModel: String {
        get { UserDefaults.standard.string(forKey: "llmModel") ?? "deepseek-chat" }
        set { UserDefaults.standard.set(newValue, forKey: "llmModel") }
    }

    func nextColor() -> String {
        let c = THOUGHT_COLORS[colorIndex % THOUGHT_COLORS.count]
        colorIndex = (colorIndex + 1) % THOUGHT_COLORS.count
        return c
    }

    func save(thought: String, selectedText: String, appName: String,
              browserURL: String, screenshotPath: String?) -> (ok: Bool, savedTo: String) {
        if backend == "notes" {
            return saveToAppleNotes(thought: thought, selectedText: selectedText, appName: appName)
        } else {
            return saveToObsidian(thought: thought, selectedText: selectedText,
                                  appName: appName, browserURL: browserURL,
                                  screenshotPath: screenshotPath)
        }
    }

    private func saveToObsidian(thought: String, selectedText: String,
                                appName: String, browserURL: String,
                                screenshotPath: String?) -> (ok: Bool, savedTo: String) {
        guard !vaultPath.isEmpty else { return (false, "") }
        let vault = NSString(string: vaultPath).expandingTildeInPath
        let fm = FileManager.default

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let timeStr = tf.string(from: Date())

        let dayDir = "\(vault)/01_daily/\(dateStr)"
        try? fm.createDirectory(atPath: dayDir, withIntermediateDirectories: true)

        let filePath = "\(dayDir)/Daily random thoughts.md"
        let savedTo = "01_daily/\(dateStr)/Daily random thoughts.md"

        var source = ""
        if !browserURL.isEmpty, !browserURL.hasPrefix("app://"),
           let parsed = URL(string: browserURL) {
            let host = parsed.host ?? ""
            let path = parsed.path.count <= 40 ? parsed.path : String(parsed.path.prefix(37)) + "..."
            source = "[\(host)\(path)](\(browserURL))"
        }

        var screenshotFilename: String? = nil
        if let path = screenshotPath, let data = fm.contents(atPath: path) {
            let ts = DateFormatter()
            ts.dateFormat = "yyyyMMdd_HHmmss"
            screenshotFilename = "tc_\(ts.string(from: Date())).png"
            let attachDir = "\(vault)/attachments"
            try? fm.createDirectory(atPath: attachDir, withIntermediateDirectories: true)
            fm.createFile(atPath: "\(attachDir)/\(screenshotFilename!)", contents: data)
            try? fm.removeItem(atPath: path)
        }

        let color = nextColor()
        var lines = [String]()
        lines.append("")
        lines.append("> [!thought-\(color)] \(timeStr)")
        lines.append("> \(thought)")
        if let sf = screenshotFilename {
            lines.append("> ![[\(sf)]]")
        }
        if !selectedText.isEmpty {
            var safe = selectedText
            safe = safe.replacingOccurrences(of: "```", with: "` ` `")
            let quoted = safe.components(separatedBy: "\n").joined(separator: "\n> > ")
            let sourceTag = !source.isEmpty ? " \u{3010}\(source)\u{3011}" : (!appName.isEmpty ? " \u{3010}\(appName)\u{3011}" : "")
            lines.append("> > \(quoted)\(sourceTag)")
        } else if !source.isEmpty {
            lines.append("> \(source)")
        }
        lines.append("")

        let entry = lines.joined(separator: "\n")

        if fm.fileExists(atPath: filePath) {
            if let fh = FileHandle(forWritingAtPath: filePath) {
                fh.seekToEndOfFile()
                fh.write(entry.data(using: .utf8)!)
                fh.closeFile()
            }
        } else {
            let header = "# Random Thoughts \u{2014} \(dateStr)\n"
            try? (header + entry).write(toFile: filePath, atomically: true, encoding: .utf8)
        }

        return (true, savedTo)
    }

    private func saveToAppleNotes(thought: String, selectedText: String,
                                  appName: String) -> (ok: Bool, savedTo: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let timeStr = tf.string(from: Date())
        let noteTitle = "Thoughts \u{2014} \(dateStr)"

        var body = "\u{1F535} \(timeStr)<br>\(thought)"
        if !selectedText.isEmpty {
            let sourceTag = !appName.isEmpty ? " <span style=\"font-style:normal;font-size:0.8em\">\u{2014} \(appName)</span>" : ""
            body += "<br><span style=\"font-style:italic;color:#8e8e93\">\(selectedText)\(sourceTag)</span>"
        }
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "<br>")

        let script = """
        tell application "Notes"
            set noteFound to false
            repeat with n in notes of default account
                if name of n is "\(noteTitle)" then
                    set body of n to (body of n) & "<br><br>" & "\(escaped)"
                    set noteFound to true
                    exit repeat
                end if
            end repeat
            if not noteFound then
                make new note at default account with properties {name:"\(noteTitle)", body:"\(escaped)"}
            end if
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do {
            try proc.run()
            proc.waitUntilExit()
            return (proc.terminationStatus == 0, noteTitle)
        } catch {
            fputs("[TC] Apple Notes error: \(error)\n", stderr)
            return (false, "")
        }
    }
}
