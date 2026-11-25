import Foundation

/// Menjalankan "tombol perintah" milik pengguna (zsh login shell) dan mengingat hasil terakhirnya.
/// Output setiap perintah dicatat di ~/Library/Logs/Bilah/perintah.log.
final class CommandRunner {
    enum Status: Equatable { case running, succeeded, failed }

    static let shared = CommandRunner()
    static let changed = Notification.Name("BilahCommandsChanged")
    static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Bilah/perintah.log")
    }

    private var states: [String: (status: Status, at: Date)] = [:]

    /// Status untuk digambar: sedang jalan, atau hasil yang selesai < 6 detik lalu.
    func status(_ id: String) -> Status? {
        guard let s = states[id] else { return nil }
        if s.status != .running, Date().timeIntervalSince(s.at) > 6 { return nil }
        return s.status
    }

    func run(id: String, name: String, script: String, directory: String) {
        guard status(id) != .running else { return }
        set(id, .running)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script]
        let dir = (directory as NSString).expandingTildeInPath
        if !dir.isEmpty { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let ok = proc.terminationStatus == 0
            Self.log(name: name, script: script, status: proc.terminationStatus, output: data)
            DispatchQueue.main.async { self?.set(id, ok ? .succeeded : .failed) }
        }
        do {
            try p.run()
        } catch {
            Self.log(name: name, script: script, status: -1, output: Data("\(error)".utf8))
            set(id, .failed)
        }
    }

    private func set(_ id: String, _ status: Status) {
        states[id] = (status, Date())
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// Satu antrean untuk menulis log, supaya perintah yang selesai bersamaan tidak saling menimpa.
    private static let logQueue = DispatchQueue(label: "bilah.commands.log")

    private static func log(name: String, script: String, status: Int32, output: Data) {
        logQueue.sync { append(name: name, script: script, status: status, output: output) }
    }

    private static func append(name: String, script: String, status: Int32, output: Data) {
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tail = String(decoding: output.suffix(8000), as: UTF8.self)
        let entry = "=== \(ISO8601DateFormatter().string(from: Date())) · \(name) · exit \(status)\n$ \(script)\n\(tail)\n\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(entry.utf8))
            try? h.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
