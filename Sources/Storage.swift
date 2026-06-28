import Cocoa

class LocalStorage {
    static let shared = LocalStorage()
    private var colorIndex = 0

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

    /// Auto-install thought-cards.css into the Obsidian vault's snippets folder
    func installObsidianSnippet() {
        let folder = NSString(string: vaultPath).expandingTildeInPath
        let fm = FileManager.default
        // Walk up to find vault root
        var dir = folder
        while dir != "/" && !dir.isEmpty {
            if fm.fileExists(atPath: "\(dir)/.obsidian") { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        guard fm.fileExists(atPath: "\(dir)/.obsidian") else { return }

        let snippetsDir = "\(dir)/.obsidian/snippets"
        try? fm.createDirectory(atPath: snippetsDir, withIntermediateDirectories: true)

        let cssPath = "\(snippetsDir)/thought-cards.css"
        if !fm.fileExists(atPath: cssPath) {
            try? thoughtCardsCSS.write(toFile: cssPath, atomically: true, encoding: .utf8)
        }

        // Enable in appearance.json
        let appearancePath = "\(dir)/.obsidian/appearance.json"
        var appearance: [String: Any] = [:]
        if let data = fm.contents(atPath: appearancePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            appearance = json
        }
        var snippets = appearance["enabledCssSnippets"] as? [String] ?? []
        if !snippets.contains("thought-cards") {
            snippets.append("thought-cards")
            appearance["enabledCssSnippets"] = snippets
            if let data = try? JSONSerialization.data(withJSONObject: appearance, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: appearancePath))
            }
        }
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
        let folder = NSString(string: vaultPath).expandingTildeInPath
        let fm = FileManager.default

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let timeStr = tf.string(from: Date())

        let dayDir = "\(folder)/\(dateStr)"
        try? fm.createDirectory(atPath: dayDir, withIntermediateDirectories: true)
        let fileName = "Thoughts.md"
        let filePath = "\(dayDir)/\(fileName)"
        // savedTo must be relative to vault root for obsidian:// deep links
        var vaultRoot = folder
        while vaultRoot != "/" && !vaultRoot.isEmpty {
            if fm.fileExists(atPath: "\(vaultRoot)/.obsidian") { break }
            vaultRoot = (vaultRoot as NSString).deletingLastPathComponent
        }
        let savedTo: String
        if filePath.hasPrefix(vaultRoot + "/") {
            savedTo = String(filePath.dropFirst(vaultRoot.count + 1))
        } else {
            savedTo = "\(dateStr)/\(fileName)"
        }

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
            let attachDir = "\(dayDir)/attachments"
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

    private let thoughtCardsCSS = """
    /* ThoughtCapture — styled thought callouts */
    .callout[data-callout^="thought"] {
      --callout-icon: lucide-sparkles;
      border: none; border-radius: 10px; padding: 8px 14px;
      margin: 6px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.06);
    }
    .callout[data-callout^="thought"] .callout-title {
      font-size: 0.78em; opacity: 0.6; font-weight: 400; padding: 0;
    }
    .callout[data-callout^="thought"] .callout-title-inner { font-weight: 400; }
    .callout[data-callout^="thought"] .callout-content { padding: 2px 0 0 0; font-size: 0.95em; }
    .callout[data-callout^="thought"] .callout-content blockquote {
      border-left: 2px solid rgba(0,0,0,0.15); margin: 4px 0 0 0;
      padding: 2px 0 2px 10px; font-size: 0.88em; opacity: 0.7; font-style: italic;
    }
    .callout[data-callout="thought-coral"] { --callout-color: 230,107,128; background: linear-gradient(135deg, rgba(245,166,115,0.13), rgba(230,107,128,0.13)); }
    .callout[data-callout="thought-blue"] { --callout-color: 97,128,217; background: linear-gradient(135deg, rgba(140,199,242,0.13), rgba(97,128,217,0.13)); }
    .callout[data-callout="thought-purple"] { --callout-color: 158,115,209; background: linear-gradient(135deg, rgba(217,179,242,0.13), rgba(158,115,209,0.13)); }
    .callout[data-callout="thought-green"] { --callout-color: 89,179,158; background: linear-gradient(135deg, rgba(153,230,191,0.13), rgba(89,179,158,0.13)); }
    .callout[data-callout="thought-amber"] { --callout-color: 224,148,77; background: linear-gradient(135deg, rgba(242,204,115,0.13), rgba(224,148,77,0.13)); }
    .callout[data-callout="thought-olive"] { --callout-color: 122,184,102; background: linear-gradient(135deg, rgba(179,217,140,0.13), rgba(122,184,102,0.13)); }
    .callout[data-callout="thought-pink"] { --callout-color: 209,89,122; background: linear-gradient(135deg, rgba(242,140,166,0.13), rgba(209,89,122,0.13)); }
    .callout[data-callout="thought-steel"] { --callout-color: 82,148,191; background: linear-gradient(135deg, rgba(128,191,224,0.13), rgba(82,148,191,0.13)); }
    .callout[data-callout="thought"] { --callout-color: 140,140,160; background: rgba(140,140,160,0.08); }
    """

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
