import AppKit
import QuartzCore

enum Player: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var tint: NSColor {
        self == .spotify
            ? NSColor(srgbRed: 0.12, green: 0.84, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.98, green: 0.28, blue: 0.38, alpha: 1)
    }
}

struct Track: Equatable {
    var player: Player
    var playing: Bool
    var title: String
    var artist: String
    var position: Double
    var duration: Double
    var stamp: CFTimeInterval

    /// Posisi diinterpolasi lokal di antara polling supaya cincin progres jalan halus.
    var livePosition: Double {
        playing ? min(duration, position + (CACurrentMediaTime() - stamp)) : position
    }
}

/// Baca dan kontrol Spotify / Music lewat AppleScript (osascript di thread latar).
/// MediaRemote sudah dikunci Apple sejak macOS 15.4, jadi ini jalur yang masih bisa dipakai.
/// Aplikasi musik tidak pernah dibuka paksa: hanya ditanya kalau memang sedang jalan.
final class NowPlayingSource {
    private let queue = DispatchQueue(label: "bilah.nowplaying")
    private static let sep = "|~|"

    func fetch(_ done: @escaping (Track?) -> Void) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = Player.allCases.filter { running.contains($0.bundleID) }
        guard !players.isEmpty else { done(nil); return }
        queue.async {
            let tracks = players.compactMap(Self.query)
            let pick = tracks.first(where: \.playing) ?? tracks.first
            DispatchQueue.main.async { done(pick) }
        }
    }

    func send(_ command: String, to player: Player) {
        queue.async { _ = Self.osascript("tell application \"\(player.rawValue)\" to \(command)") }
    }

    private static func query(_ p: Player) -> Track? {
        let script = """
        if application "\(p.rawValue)" is running then
            tell application "\(p.rawValue)"
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
        if p == .spotify { duration /= 1000 } // Spotify memberi milidetik
        return Track(player: p, playing: parts[0] == "playing", title: parts[1], artist: parts[2],
                     position: num(parts[3]), duration: duration, stamp: CACurrentMediaTime())
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

final class NowPlayingWidget: Widget {
    let kind = WidgetKind.nowPlaying
    private let source = NowPlayingSource()
    private var track: Track?
    private var ticks = 0
    private var inFlight = false
    private let views = ViewSet<NowPlayingView>()

    func makeView() -> WidgetView {
        let v = NowPlayingView()
        v.track = track
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            self.handle(v.zone(at: p))
        }
        views.add(v)
        return v
    }

    func tick() {
        ticks += 1
        if ticks % 2 == 1 { poll() }
    }

    private func poll() {
        guard !inFlight else { return }
        inFlight = true
        source.fetch { [weak self] t in
            guard let self else { return }
            self.inFlight = false
            self.track = t
            self.views.forEach { $0.track = t }
        }
    }

    private func handle(_ zone: NowPlayingView.Zone) {
        guard var t = track else { return }
        switch zone {
        case .prev: source.send("previous track", to: t.player)
        case .next: source.send("next track", to: t.player)
        case .toggle:
            // Ubah tampilan dulu supaya terasa instan, lalu konfirmasi lewat polling.
            t.position = t.livePosition
            t.stamp = CACurrentMediaTime()
            t.playing.toggle()
            track = t
            views.forEach { $0.track = t }
            source.send("playpause", to: t.player)
        case .info:
            NSRunningApplication.runningApplications(withBundleIdentifier: t.player.bundleID).first?.activate()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
    }
}

final class NowPlayingView: WidgetView {
    enum Zone { case info, prev, toggle, next }
    private static let zones: [Zone] = [.prev, .toggle, .next]
    private static let zoneWidth: CGFloat = 31

    var track: Track? {
        didSet {
            animating = track?.playing == true
            needsDisplay = true
        }
    }

    override var highlightsWhole: Bool { false }

    init() { super.init(width: 268) }
    required init?(coder: NSCoder) { fatalError() }

    private var controlsX: CGFloat { bounds.width - Self.zoneWidth * 3 - 4 }

    func zone(at p: NSPoint) -> Zone {
        guard track != nil, p.x >= controlsX else { return .info }
        let i = Int((p.x - controlsX) / Self.zoneWidth)
        return Self.zones[min(2, max(0, i))]
    }

    private func center(_ i: Int) -> NSPoint {
        NSPoint(x: controlsX + Self.zoneWidth * (CGFloat(i) + 0.5), y: bounds.midY)
    }

    override func drawContent(_ b: NSRect) {
        guard let t = track else {
            Draw.symbol("music.note", size: 12, weight: .medium, color: Theme.faint, center: NSPoint(x: 17, y: b.midY))
            Draw.centered("Nggak ada yang diputar", Theme.font(11, .medium), Theme.secondary,
                          x: 32, width: b.width - 40, centerY: b.midY)
            return
        }
        let pressedZone = pressPoint.map(zone(at:))
        if pressedZone == .info {
            Draw.roundedRect(NSRect(x: 0, y: 0, width: controlsX, height: b.height), radius: Theme.radius, fill: Theme.pillPressed)
        }

        // Equalizer mini: bergerak saat main, rata saat jeda.
        let time = Animator.now
        for i in 0..<4 {
            let wave = abs(sin(time * (3.1 + Double(i) * 1.3) + Double(i) * 1.7))
            let h: CGFloat = t.playing ? 3 + 11 * CGFloat(wave) : 3
            let r = NSRect(x: 9 + CGFloat(i) * 4.2, y: b.midY + 7 - h, width: 2.6, height: h)
            Draw.roundedRect(r, radius: 1.3, fill: t.player.tint.withAlphaComponent(t.playing ? 1 : 0.5))
        }

        let textWidth = controlsX - 32 - 6
        Draw.line(t.title, Theme.font(11, .semibold), Theme.text, x: 32, y: 3, width: textWidth)
        Draw.line(t.artist, Theme.font(9.5), Theme.secondary, x: 32, y: 16, width: textWidth)

        let symbols = ["backward.fill", t.playing ? "pause.fill" : "play.fill", "forward.fill"]
        for i in 0..<3 {
            let c = center(i)
            if pressedZone == Self.zones[i] { Draw.circle(c, 12.5, Theme.pillPressed) }
            Draw.symbol(symbols[i], size: i == 1 ? 10.5 : 9, weight: .bold, color: Theme.text, center: c)
        }

        // Progres lagu sebagai cincin di sekeliling tombol play.
        let frac = t.duration > 0 ? CGFloat(t.livePosition / t.duration) : 0
        Draw.ring(center(1), 11.5, width: 1.8, color: Theme.track)
        Draw.ring(center(1), 11.5, width: 1.8, color: t.player.tint, to: frac)
    }
}
