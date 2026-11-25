import AppKit
import Combine
import Security

/// Cek rilis terbaru di GitHub, unduh Bilah.zip, verifikasi tanda tangan, ganti app, lalu buka ulang.
final class Updater: ObservableObject {
    static let repo = "sanadunt/bilah"
    static let repoURL = URL(string: "https://github.com/\(repo)")!
    static let assetName = "Bilah.zip"

    struct Release: Equatable {
        var version: String
        var notes: String
        var asset: URL
        var page: URL
        var published: Date?
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing
        case failed(String)
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastChecked: Date?
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "autoCheckUpdates") } }

    private var timer: Timer?
    private var progressObservation: NSKeyValueObservation?

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var updateAvailable: Bool {
        guard let latest else { return false }
        return Self.isNewer(latest.version, than: Self.currentVersion)
    }

    init() {
        autoCheck = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
    }

    /// Cek 5 detik setelah buka, lalu tiap 6 jam (kalau diaktifkan).
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.autoCheck else { return }
            self.check()
        }
        let t = Timer(timeInterval: 6 * 3600, target: self, selector: #selector(periodicCheck), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func periodicCheck() {
        if autoCheck { check() }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    func check() {
        switch phase {
        case .checking, .downloading, .installing: return
        default: break
        }
        phase = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Bilah-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let result = Self.parse(data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastChecked = Date()
                switch result {
                case .success(let release):
                    self.latest = release
                    self.phase = self.updateAvailable ? .available : .upToDate
                case .failure(let message):
                    self.phase = .failed(message)
                }
            }
        }.resume()
    }

    private enum CheckResult {
        case success(Release)
        case failure(String)
    }

    private static func parse(data: Data?, response: URLResponse?, error: Error?) -> CheckResult {
        if let error { return .failure("Tidak bisa menghubungi GitHub: \(error.localizedDescription)") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .failure("Belum ada rilis di GitHub.") }
        guard status == 200, let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            return .failure("Jawaban GitHub tidak terbaca (HTTP \(status)).")
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            return .failure("Rilis \(tag) tidak punya file \(assetName).")
        }
        let published = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return .success(Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                                notes: json["body"] as? String ?? "", asset: url, page: page, published: published))
    }

    // MARK: Pasang

    func install() {
        guard let release = latest, updateAvailable else { return }
        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            phase = .failed("Folder \(appURL.deletingLastPathComponent().path) tidak bisa ditulis. Pindahkan Bilah ke Applications dulu.")
            return
        }
        phase = .downloading(0)
        let task = URLSession.shared.downloadTask(with: release.asset) { [weak self] file, _, error in
            let result: Result<URL, UpdateError>
            if let file {
                result = Self.prepare(download: file, expectedVersion: release.version)
            } else {
                result = .failure(.message("Unduhan gagal: \(error?.localizedDescription ?? "tidak diketahui")"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressObservation = nil
                switch result {
                case .success(let newApp):
                    self.phase = .installing
                    self.swapAndRelaunch(newApp: newApp, replacing: appURL)
                case .failure(.message(let m)):
                    self.phase = .failed(m)
                }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { self?.phase = .downloading(p.fractionCompleted) }
        }
        task.resume()
    }

    private enum UpdateError: Error { case message(String) }

    /// Ekstrak zip ke folder sementara dan pastikan isinya Bilah asli dengan versi yang diharapkan.
    private static func prepare(download: URL, expectedVersion: String) -> Result<URL, UpdateError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("bilah-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(assetName)
            try fm.moveItem(at: download, to: zip)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, work.appendingPathComponent("out").path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { return .failure(.message("Gagal mengekstrak \(assetName).")) }
        } catch {
            return .failure(.message("Gagal menyiapkan update: \(error.localizedDescription)"))
        }
        let newApp = work.appendingPathComponent("out/Bilah.app")
        guard let info = Bundle(url: newApp)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String, version == expectedVersion else {
            return .failure(.message("Isi update tidak cocok dengan rilis \(expectedVersion)."))
        }
        guard signatureMatchesCurrent(newApp) else {
            return .failure(.message("Tanda tangan update tidak cocok dengan Bilah yang terpasang. Update dibatalkan."))
        }
        return .success(newApp)
    }

    /// Update harus ditandatangani sertifikat yang sama dengan app yang sedang jalan.
    /// Kalau app yang jalan adalah build ad-hoc (pengembangan), cukup cek identifier dan tanda tangan valid.
    private static func signatureMatchesCurrent(_ app: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }

        var selfCode: SecCode?
        var requirement: SecRequirement?
        if SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode {
            var selfStatic: SecStaticCode?
            SecCodeCopyStaticCode(selfCode, [], &selfStatic)
            if let selfStatic { SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) }
        }
        var text: CFString?
        if let requirement { SecRequirementCopyString(requirement, [], &text) }
        if requirement == nil || (text as String?)?.contains("cdhash") == true {
            requirement = nil
            SecRequirementCreateWithString("identifier \"local.bilah.app\"" as CFString, [], &requirement)
        }
        guard let requirement else { return false }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    /// Skrip kecil menunggu Bilah keluar, menukar app (dengan cadangan), lalu membukanya lagi.
    private func swapAndRelaunch(newApp: URL, replacing appURL: URL) {
        let script = """
        while kill -0 "$OLD_PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.old"
        if mv "$DEST" "$DEST.old"; then
            if mv "$NEW" "$DEST"; then rm -rf "$DEST.old"; else mv "$DEST.old" "$DEST"; fi
        fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.environment = ["OLD_PID": "\(getpid())", "DEST": appURL.path, "NEW": newApp.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed("Gagal menjalankan pemasang: \(error.localizedDescription)")
        }
    }

    // MARK: Pindah ke Applications

    static var isInApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Salin ke /Applications (atau ~/Applications kalau tidak bisa ditulis), buka dari sana, tutup yang ini.
    static func moveToApplications() -> String? {
        let fm = FileManager.default
        let system = URL(fileURLWithPath: "/Applications")
        let user = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        let folder = fm.isWritableFile(atPath: system.path) ? system : user
        let dest = folder.appendingPathComponent("Bilah.app")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
        } catch {
            return "Gagal menyalin: \(error.localizedDescription)"
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return nil
    }
}
