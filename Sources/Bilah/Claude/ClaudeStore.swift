import AppKit

enum ClaudeState: String, Codable {
    case working, waiting, done, idle

    /// Urutan tampil: yang butuh perhatian duluan.
    var rank: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        }
    }

    var color: NSColor? {
        switch self {
        case .waiting: Theme.amber
        case .working: Theme.coral
        case .done: Theme.green
        case .idle: nil
        }
    }

    var title: String {
        switch self {
        case .waiting: "Nunggu kamu"
        case .working: "Lagi kerja"
        case .done: "Selesai"
        case .idle: "Siap"
        }
    }
}

struct ClaudeSession: Codable, Equatable {
    var id: String
    var state: ClaudeState
    var project: String
    /// Kapan state sekarang dimulai (detik epoch).
    var since: Double
    var updated: Double
    /// Tool yang sedang dipakai, mis. "Edit · Widget.swift".
    var detail: String?
    /// Aplikasi tempat sesi berjalan (Terminal, iTerm, VS Code, app Claude), untuk dibuka saat diketuk.
    var appPID: Int32?
    var appBundle: String?
}

/// Satu file JSON per sesi Claude Code. Ditulis oleh `Bilah hook`, dibaca widget tiap detik.
enum ClaudeStore {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["BILAH_STATE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilah/claude", isDirectory: true)
    }

    private static func file(_ id: String) -> URL {
        let safe = String(id.unicodeScalars.prefix(80).map {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" ? Character($0) : "_"
        })
        return directory.appendingPathComponent(safe + ".json")
    }

    static func read(_ id: String) -> ClaudeSession? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(ClaudeSession.self, from: data)
    }

    static func write(_ s: ClaudeSession) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: file(s.id), options: .atomic)
    }

    static func remove(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }

    static func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" { try? FileManager.default.removeItem(at: f) }
    }

    /// Sesi aktif, urut dari yang paling butuh perhatian. Sesi basi (>12 jam) dihapus,
    /// sesi selesai/diam yang lebih dari 3 jam disembunyikan.
    static func loadAll(now: Double = Date().timeIntervalSince1970) -> [ClaudeSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var out: [ClaudeSession] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let s = try? JSONDecoder().decode(ClaudeSession.self, from: data) else { continue }
            let age = now - s.updated
            if age > 12 * 3600 { try? FileManager.default.removeItem(at: f); continue }
            if (s.state == .done || s.state == .idle) && age > 3 * 3600 { continue }
            out.append(s)
        }
        return out.sorted { ($0.state.rank, -$0.updated) < ($1.state.rank, -$1.updated) }
    }
}

/// Mode `Bilah hook`: dipanggil Claude Code lewat hooks, baca JSON dari stdin, tulis status sesi.
/// Tidak pernah mencetak apa pun dan selalu keluar dengan kode 0, jadi tidak bisa memblokir tool.
enum ClaudeHook {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let id = payload["session_id"] as? String ?? "default"
        let event = payload["hook_event_name"] as? String ?? ""

        if event == "SessionEnd" {
            ClaudeStore.remove(id)
            return
        }
        guard let state = state(for: event, payload: payload) else { return }

        let now = Date().timeIntervalSince1970
        let cwd = payload["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Claude" : URL(fileURLWithPath: cwd).lastPathComponent
        var s = ClaudeStore.read(id) ?? ClaudeSession(id: id, state: state, project: project, since: now, updated: now)
        if s.state != state {
            s.state = state
            s.since = now
        }
        s.project = project
        s.updated = now
        switch event {
        case "PreToolUse": s.detail = describeTool(payload)
        case "UserPromptSubmit", "Stop", "SessionStart": s.detail = nil
        default: break
        }
        if s.appBundle == nil || event == "SessionStart" || event == "UserPromptSubmit", let host = hostApp() {
            s.appPID = host.pid
            s.appBundle = host.bundle
        }
        ClaudeStore.write(s)
    }

    /// Ringkasan tool dari payload PreToolUse: "Edit · Widget.swift", "Bash · swift build", "Grep · “pola”".
    static func describeTool(_ payload: [String: Any]) -> String? {
        guard let name = payload["tool_name"] as? String else { return nil }
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        func clip(_ s: String, _ n: Int = 40) -> String {
            let line = s.split(separator: "\n").first.map(String.init) ?? s
            return line.count > n ? String(line.prefix(n - 1)) + "…" : line
        }
        let summary: String?
        if let path = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String {
            summary = (path as NSString).lastPathComponent
        } else if let command = input["command"] as? String {
            summary = clip(command)
        } else if let pattern = input["pattern"] as? String {
            summary = "“\(clip(pattern, 30))”"
        } else if let url = (input["url"] as? String).flatMap(URL.init(string:)) {
            summary = url.host
        } else if let query = input["query"] as? String {
            summary = clip(query, 30)
        } else if let description = input["description"] as? String {
            summary = clip(description, 34)
        } else {
            summary = nil
        }
        let short = name.hasPrefix("mcp__") ? (name.split(separator: "_").last.map(String.init) ?? name) : name
        return summary.map { "\(short) · \($0)" } ?? short
    }

    /// Cari aplikasi (Terminal, iTerm, VS Code, app Claude, …) di antara proses induk hook ini.
    static func hostApp() -> (pid: Int32, bundle: String)? {
        var pid = getppid()
        for _ in 0..<20 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
               let id = app.bundleIdentifier {
                return (pid, id)
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1 else { return nil }
            pid = parent
        }
        return nil
    }

    static func state(for event: String, payload: [String: Any]) -> ClaudeState? {
        switch event {
        case "SessionStart": return .idle
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact": return .working
        case "Stop": return .done
        case "Notification":
            let type = payload["notification_type"] as? String
            let message = (payload["message"] as? String ?? "").lowercased()
            // "Claude is waiting for your input" = giliran sudah selesai, bukan minta izin.
            if type == "idle_prompt" || message.contains("waiting for your input") { return .done }
            return .waiting
        default: return nil
        }
    }
}

enum HookConfig {
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", "*"), ("PostToolUse", "*"),
        ("Notification", nil), ("Stop", nil), ("SessionEnd", nil),
    ]

    static var currentExecutable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    static func command(executable: String) -> String {
        "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' hook"
    }

    private static func entry(_ command: String, matcher: String?) -> [String: Any] {
        var e: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
        if let matcher { e["matcher"] = matcher }
        return e
    }

    /// Entri hook milik Bilah (path apa pun), dipakai untuk mengganti versi lama tanpa dobel.
    private static func isBilahEntry(_ entry: Any) -> Bool {
        guard let hooks = (entry as? [String: Any])?["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String).map { $0.contains("Bilah") && $0.hasSuffix(" hook") } ?? false }
    }

    private static func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    /// Potongan "hooks" untuk disalin manual.
    static func json(executable: String) -> String {
        let cmd = command(executable: executable)
        var hooks: [String: Any] = [:]
        for e in events { hooks[e.name] = [entry(cmd, matcher: e.matcher)] }
        return String(decoding: encode(["hooks": hooks]), as: UTF8.self)
    }

    /// Lokasi settings.json Claude Code yang ada di Mac ini (~/.claude dan folder ~/.claude-* lain).
    static func candidateSettingsFiles() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let dirs = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil,
                                                                 options: [])) ?? []
        return dirs.filter { $0.lastPathComponent == ".claude" || $0.lastPathComponent.hasPrefix(".claude-") }
            .map { $0.appendingPathComponent("settings.json") }
            .filter { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
            .sorted { $0.path < $1.path }
    }

    static func isInstalled(in settings: URL) -> Bool {
        guard let data = try? Data(contentsOf: settings),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        let cmd = command(executable: currentExecutable)
        return events.allSatisfy { e in
            ((hooks[e.name] as? [Any]) ?? []).contains { item in
                ((item as? [String: Any])?["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } ?? false
            }
        }
    }

    /// Gabungkan hook Bilah ke settings.json. Bagian lain dibiarkan; file lama dicadangkan dulu.
    static func install(into settings: URL) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settings), !data.isEmpty {
            guard let parsed = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw NSError(domain: "Bilah", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json bukan objek JSON."])
            }
            root = parsed
            let backup = settings.appendingPathExtension("bilah-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settings, to: backup)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let cmd = command(executable: currentExecutable)
        for e in events {
            var list = (hooks[e.name] as? [Any] ?? []).filter { !isBilahEntry($0) }
            list.append(entry(cmd, matcher: e.matcher))
            hooks[e.name] = list
        }
        root["hooks"] = hooks
        try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(root).write(to: settings, options: .atomic)
    }

    /// Hapus hook Bilah saja.
    static func uninstall(from settings: URL) throws {
        guard let data = try? Data(contentsOf: settings),
              var root = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else { return }
        for e in events {
            let list = (hooks[e.name] as? [Any] ?? []).filter { !isBilahEntry($0) }
            hooks[e.name] = list.isEmpty ? nil : list
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try encode(root).write(to: settings, options: .atomic)
    }
}
