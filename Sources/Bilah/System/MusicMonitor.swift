import AppKit
import Combine
import QuartzCore

// MARK: - Katalog aplikasi musik

/// Aplikasi yang biasa memutar musik/video. Aplikasi lain tetap didukung lewat "Pilih aplikasi lain…".
enum MusicApps {
    static let spotify = "com.spotify.client"
    static let music = "com.apple.Music"

    static let known: [(id: String, name: String)] = [
        (spotify, "Spotify"), (music, "Music"),
        ("com.google.Chrome", "Google Chrome"), ("com.apple.Safari", "Safari"),
        ("company.thebrowser.Browser", "Arc"), ("com.brave.Browser", "Brave"),
        ("org.mozilla.firefox", "Firefox"), ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.operasoftware.Opera", "Opera"), ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.tidal.desktop", "TIDAL"), ("com.deezer.deezer-desktop", "Deezer"),
        ("com.amazon.music", "Amazon Music"), ("org.videolan.vlc", "VLC"),
        ("com.colliderli.iina", "IINA"), ("com.apple.podcasts", "Podcasts"), ("com.apple.TV", "TV"),
    ]

    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(_ id: String) -> String {
        if let k = known.first(where: { $0.id == id }) { return k.name }
        guard let url = url(id) else { return id }
        return (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
    }

    static func icon(_ id: String) -> NSImage? { url(id).map { NSWorkspace.shared.icon(forFile: $0.path) } }

    static func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    static func tint(_ id: String) -> NSColor {
        switch id {
        case spotify: NSColor(srgbRed: 0.12, green: 0.84, blue: 0.38, alpha: 1)
        case music: NSColor(srgbRed: 0.98, green: 0.28, blue: 0.38, alpha: 1)
        case "com.google.Chrome", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi":
            NSColor(srgbRed: 1.0, green: 0.33, blue: 0.30, alpha: 1)
        default: Theme.teal
        }
    }

    /// Bawaan: Spotify kalau terpasang, kalau tidak Music.
    static var defaultApp: String { url(spotify) != nil ? spotify : music }

    /// Daftar pilihan di pengaturan: yang terpasang dari katalog + tambahan pengguna + yang pernah memutar.
    static func choices(extra: [String]) -> [String] {
        var ids = known.map(\.id).filter { url($0) != nil }
        for id in extra where !ids.contains(id) && url(id) != nil { ids.append(id) }
        return ids
    }
}

// MARK: - Data Now Playing

struct NowPlayingInfo: Equatable {
    var bundleID: String?
    var appName: String?
    var title = ""
    var artist = ""
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 0
    var timestamp: Double?
    var playing = false

    var hasTrack: Bool { !title.isEmpty && bundleID != nil }

    /// Posisi sekarang: posisi tercatat + waktu yang berlalu sejak dicatat (kalau sedang diputar).
    var currentPosition: Double {
        guard playing, let timestamp else { return elapsed }
        return min(duration > 0 ? duration : .infinity, elapsed + (Date().timeIntervalSince1970 - timestamp) * max(rate, 1))
    }

    func track() -> Track? {
        guard hasTrack, let id = bundleID else { return nil }
        return Track(bundleID: id, appName: appName ?? MusicApps.name(id), playing: playing, title: title, artist: artist,
                     position: currentPosition, duration: duration, stamp: CACurrentMediaTime())
    }
}

struct Track: Equatable {
    var bundleID: String
    var appName: String
    var playing: Bool
    var title: String
    var artist: String
    var position: Double
    var duration: Double
    var stamp: CFTimeInterval

    var tint: NSColor { MusicApps.tint(bundleID) }

    /// Posisi diinterpolasi lokal di antara kabar supaya cincin progres jalan halus.
    var livePosition: Double {
        playing ? min(duration, position + (CACurrentMediaTime() - stamp)) : position
    }
}

enum MusicCommand: String {
    case toggle, play, pause, next, previous
}

// MARK: - Sumber universal: MediaRemote lewat /usr/bin/perl

/// Menjalankan helper (Helpers/MediaRemoteBridge.m) di dalam /usr/bin/perl, karena sejak macOS 15.4
/// MediaRemote hanya melayani proses milik Apple. Helper mengirim JSON tiap info berubah dan menerima perintah.
final class MediaRemoteBridge {
    private static let script = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "bilah_mediaremote_main") or die "symbol";
    DynaLoader::dl_install_xsub("main::run", $sym);
    run();
    """

    static var dylib: URL? {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("libBilahMediaRemote.dylib"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var onInfo: ((NowPlayingInfo) -> Void)?
    var onStop: (() -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var stopping = false

    /// false = helper tidak tersedia (mis. dijalankan tanpa bundel .app).
    @discardableResult
    func start() -> Bool {
        guard process == nil, let dylib = Self.dylib else { return process != nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.script, dylib.path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.terminated() }
        }
        do { try p.run() } catch { return false }
        process = p
        input = inp.fileHandleForWriting
        return true
    }

    func send(_ command: String) {
        guard let input else { return }
        try? input.write(contentsOf: Data((command + "\n").utf8))
    }

    func stop() {
        stopping = true
        try? input?.close()
        process?.terminate()
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], json["error"] == nil
            else { continue }
            restarts = 0
            var info = NowPlayingInfo()
            info.bundleID = json["bundle"] as? String
            info.appName = json["app"] as? String
            info.title = json["title"] as? String ?? ""
            info.artist = json["artist"] as? String ?? ""
            info.duration = json["duration"] as? Double ?? 0
            info.elapsed = json["elapsed"] as? Double ?? 0
            info.rate = json["rate"] as? Double ?? 0
            info.timestamp = json["timestamp"] as? Double
            info.playing = json["playing"] as? Bool ?? false
            onInfo?(info)
        }
    }

    private func terminated() {
        process = nil
        input = nil
        guard !stopping else { return }
        onStop?()
        // Coba hidupkan lagi (maks 5 kali berturut-turut tanpa kabar sukses).
        guard restarts < 5 else { return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.start() }
    }
}

// MARK: - Sumber cadangan: AppleScript (Spotify & Music saja)

/// Dipakai kalau helper MediaRemote tidak jalan. Aplikasi musik tidak pernah dibuka paksa.
final class AppleScriptMusic {
    private let queue = DispatchQueue(label: "bilah.music.applescript")
    private static let sep = "|~|"
    static let supported = [MusicApps.spotify, MusicApps.music]

    private static func appName(_ id: String) -> String { id == MusicApps.spotify ? "Spotify" : "Music" }

    func fetch(_ done: @escaping (NowPlayingInfo?) -> Void) {
        let running = Self.supported.filter(MusicApps.isRunning)
        guard !running.isEmpty else { done(nil); return }
        queue.async {
            let infos = running.compactMap(Self.query)
            let pick = infos.first(where: \.playing) ?? infos.first
            DispatchQueue.main.async { done(pick) }
        }
    }

    func send(_ command: MusicCommand, to id: String) {
        let verb: String
        switch command {
        case .toggle: verb = "playpause"
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        queue.async { _ = Self.osascript("tell application \"\(Self.appName(id))\" to \(verb)") }
    }

    private static func query(_ id: String) -> NowPlayingInfo? {
        let name = appName(id)
        let script = """
        if application "\(name)" is running then
            tell application "\(name)"
                try
                    set s to player state as string
                    set t to name of current track
                    set a to artist of current track
                    set pos to player position
                    set d to duration of current track
                    return s & "\(sep)" & t & "\(sep)" & a & "\(sep)" & (pos as string) & "\(sep)" & (d as string)
                end try
            end tell
        end if
        return ""
        """
        guard let out = osascript(script), !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: sep)
        guard parts.count == 5 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var duration = num(parts[4])
        if id == MusicApps.spotify { duration /= 1000 } // Spotify memberi milidetik
        return NowPlayingInfo(bundleID: id, appName: name, title: parts[1], artist: parts[2], duration: duration,
                              elapsed: num(parts[3]), rate: 1, timestamp: Date().timeIntervalSince1970,
                              playing: parts[0] == "playing")
    }

    private static func osascript(_ source: String, timeout: TimeInterval = 2.5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in finished.signal() }
        do { try p.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Pemantau gabungan

/// Satu sumber kebenaran "lagu apa yang sedang diputar", dipakai widget dan jendela pengaturan.
final class MusicMonitor: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    /// true = MediaRemote jalan (semua aplikasi). false = cadangan AppleScript (Spotify & Music saja).
    @Published private(set) var universal = false
    /// Aplikasi yang pernah terlihat memutar, untuk daftar pilihan di pengaturan.
    @Published private(set) var seenApps: [String] = []

    private let bridge = MediaRemoteBridge()
    private let fallback = AppleScriptMusic()
    private var fallbackTimer: Timer?

    func start() {
        bridge.onInfo = { [weak self] info in
            guard let self else { return }
            self.universal = true
            self.stopFallback()
            self.update(info)
        }
        bridge.onStop = { [weak self] in
            self?.universal = false
            self?.startFallback()
        }
        if !bridge.start() { startFallback() }
        // Kalau helper diam (mis. diblokir di macOS mendatang), pakai cadangan.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.universal else { return }
            self.startFallback()
        }
    }

    func stop() {
        bridge.stop()
        stopFallback()
    }

    private func update(_ new: NowPlayingInfo?) {
        if let id = new?.bundleID, new?.hasTrack == true, !seenApps.contains(id) { seenApps.append(id) }
        if new != info { info = new }
    }

    private func startFallback() {
        guard fallbackTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.pollFallback() }
        RunLoop.main.add(t, forMode: .common)
        fallbackTimer = t
        pollFallback()
    }

    private func stopFallback() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func pollFallback() {
        fallback.fetch { [weak self] info in
            guard let self, !self.universal else { return }
            self.update(info)
        }
    }

    /// Kirim perintah ke pemutar yang sedang aktif.
    func send(_ command: MusicCommand, to bundleID: String?) {
        if command == .toggle, var i = info {
            // Ubah tampilan dulu supaya terasa instan; kabar berikutnya akan mengoreksi.
            i.elapsed = i.currentPosition
            i.timestamp = Date().timeIntervalSince1970
            i.playing.toggle()
            info = i
        }
        if universal {
            bridge.send(command.rawValue)
        } else if let id = bundleID, AppleScriptMusic.supported.contains(id) {
            fallback.send(command, to: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.pollFallback() }
        } else {
            switch command {
            case .next: SystemShortcuts.mediaKey(SystemShortcuts.keyNext)
            case .previous: SystemShortcuts.mediaKey(SystemShortcuts.keyPrevious)
            default: SystemShortcuts.mediaKey(SystemShortcuts.keyPlay)
            }
        }
    }

    /// Buka aplikasi musik pilihan. `play`: langsung putar kalau bisa (Spotify/Music, atau aplikasi yang
    /// sedang dijeda di Now Playing); aplikasi lain (mis. browser) dibuka supaya kamu bisa memilih lagunya.
    func open(_ id: String, play: Bool) {
        guard let url = MusicApps.url(id) else { return }
        let running = MusicApps.isRunning(id)
        if play, running, universal, info?.bundleID == id {
            bridge.send(MusicCommand.play.rawValue)
            return
        }
        if play, AppleScriptMusic.supported.contains(id) {
            if running {
                fallback.send(.play, to: id)
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self?.fallback.send(.play, to: id) }
                }
            }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
