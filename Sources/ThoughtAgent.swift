import Foundation

extension LocalStorage {
    func triggerThoughtAgent(thought: String) {
        fputs("[TC] triggerThoughtAgent called: backend=\(backend) vault=\(vaultPath) mode=\(thoughtAgentMode) thought=\(thought.prefix(30))\n", stderr)
        guard backend == "obsidian", !vaultPath.isEmpty else {
            fputs("[TC] \u{1F916} Skipped: backend=\(backend) vaultPath=\(vaultPath)\n", stderr)
            return
        }
        let mode = thoughtAgentMode
        if mode == "@claude" && !thought.lowercased().contains("@claude") { return }

        let clean = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count < 2 { return }

        let vault = NSString(string: vaultPath).expandingTildeInPath
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())
        let dailyFile = "\(vault)/01_daily/\(dateStr)/Daily random thoughts.md"
        let outputDir = "\(vault)/01_daily/\(dateStr)"

        let prompt = """
        The user just jotted down a thought. Your job: figure out what they actually need (not just what they wrote), do it, and get out of the way.

        THOUGHT: "\(clean)"

        PATHS:
        - vault: \(vault)
        - today's thoughts: \(dailyFile)
        - output dir: \(outputDir)

        ## How to think about this

        The user captures fleeting thoughts \u{2014} half-formed, messy, mid-flow. Most don't need you to do anything. Some are seeds that need watering. Your value is doing the legwork they'd otherwise do later (or forget to do).

        SKIP (exit immediately, no output) if this is:
        - A note-to-self, observation, reaction
        - A record of something already done
        - An emotional reaction or fragment
        - Anything under ~10 meaningful characters

        ACT if this is:
        - A URL/paper reference \u{2192} fetch, summarize, save as md
        - A question about something \u{2192} do light research (web first, vault only to dedup)
        - A task/request \u{2192} just do it
        - An idea worth expanding \u{2192} add what they haven't thought of yet

        ## Critical rules

        1. FORWARD-LOOKING, NOT BACKWARD-LOOKING. Don't catalog what's already in the vault. Instead: what's new, what hasn't been considered, what would be surprising. Only reference vault content to avoid duplicating work.

        2. DON'T SEARCH THE WHOLE VAULT. If you must search, look at \(vault)/20_projects/ and \(vault)/10_ideas/ for active work, not daily folders.

        3. KEEP IT SHORT. 200 words useful > 2000 words thorough.

        4. FRONTMATTER on every file you create:
           ```
           ---
           source: auto-agent
           trigger: "<first 50 chars of thought>"
           date: \(dateStr)
           ---
           ```

        5. APPEND TO THOUGHTS FILE: Add inside the existing thought's callout block (use `> ` prefix). Format:
           ```
           > <one-line summary>
           > \u{2192} [[filename-without-extension]]
           ```

        6. If the thought contains @claude, everything after @claude is a direct instruction.
        """

        let bin = claudeBin
        guard !bin.isEmpty, FileManager.default.isExecutableFile(atPath: bin) else {
            fputs("[TC] \u{1F916} Skipped: claude not found at '\(claudeBin)'\n", stderr)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            fputs("[TC] \u{1F916} Thought agent triggered: \(clean.prefix(50))...\n", stderr)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = ["--dangerously-skip-permissions", "-p", prompt,
                              "--add-dir", NSString(string: "~/Documents/work").expandingTildeInPath,
                              "--model", "sonnet"]
            proc.currentDirectoryURL = URL(fileURLWithPath: vault)
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    fputs("[TC] \u{1F916} Thought agent completed\n", stderr)
                } else {
                    fputs("[TC] \u{1F916} Thought agent exit code: \(proc.terminationStatus)\n", stderr)
                }
            } catch {
                fputs("[TC] \u{1F916} Thought agent error: \(error)\n", stderr)
            }
        }
    }
}
