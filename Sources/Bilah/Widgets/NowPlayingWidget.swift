import AppKit
import Combine
import QuartzCore

/// Apa yang ditampilkan widget Musik.
enum NowPlayingDisplay: Equatable {
    /// Lagu yang sedang diputar/dijeda di aplikasi apa pun.
    case track(Track)
    /// Belum ada lagu dari aplikasi pilihan: tampilkan aplikasinya dengan tombol ▶ untuk membuka/memutar.
    case idle(bundleID: String, running: Bool)
}

final class NowPlayingWidget: Widget {
    let kind = WidgetKind.nowPlaying
    private let settings: SettingsStore
    private let music: MusicMonitor
    private let views = ViewSet<NowPlayingView>()
    private var subscription: AnyCancellable?

    init(settings: SettingsStore, music: MusicMonitor) {
        self.settings = settings
        self.music = music
        subscription = music.$info.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.push() }
        }
    }

    func makeView() -> WidgetView {
        let v = NowPlayingView()
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            self.handle(v.zone(at: p))
        }
        views.add(v)
        push()
        return v
    }

    func tick() { push() }

    /// Mode Otomatis: lagu apa pun. Mode satu aplikasi: hanya lagu dari aplikasi itu.
    private var display: NowPlayingDisplay {
        let target = settings.musicApp
        if let track = music.info?.track(), settings.musicMode == .auto || track.bundleID == target {
            return .track(track)
        }
        return .idle(bundleID: target, running: MusicApps.isRunning(target))
    }

    private func push() {
        let d = display
        views.forEach { $0.display = d }
    }

    private func handle(_ zone: NowPlayingView.Zone) {
        switch display {
        case .track(let t):
            switch zone {
            case .toggle: music.send(.toggle, to: t.bundleID)
            case .next: music.send(.next, to: t.bundleID)
            case .prev: music.send(.previous, to: t.bundleID)
            case .info:
                NSRunningApplication.runningApplications(withBundleIdentifier: t.bundleID).first?.activate()
            }
        case .idle(let id, _):
            music.open(id, play: zone == .toggle)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.push() }
    }
}

final class NowPlayingView: WidgetView {
    enum Zone { case info, prev, toggle, next }
    private static let zoneWidth: CGFloat = 31

    var display: NowPlayingDisplay = .idle(bundleID: MusicApps.music, running: false) {
        didSet {
            guard display != oldValue else { return }
            if case .track(let t) = display { animating = t.playing } else { animating = false }
            needsDisplay = true
        }
    }

    override var highlightsWhole: Bool { false }

    init() { super.init(width: 268, minWidth: 206, range: 180...420) }
    required init?(coder: NSCoder) { fatalError() }

    /// Lagu: ⏮ ⏯ ⏭ (tinggal ⏯ kalau sempit). Aplikasi siap putar: cukup ▶.
    private var zones: [Zone] {
        if case .idle = display { return [.toggle] }
        return bounds.width < 230 ? [.toggle] : [.prev, .toggle, .next]
    }

    private var controlsX: CGFloat { bounds.width - Self.zoneWidth * CGFloat(zones.count) - 4 }

    func zone(at p: NSPoint) -> Zone {
        guard p.x >= controlsX else { return .info }
        let i = Int((p.x - controlsX) / Self.zoneWidth)
        return zones[min(zones.count - 1, max(0, i))]
    }

    private func center(_ i: Int) -> NSPoint {
        NSPoint(x: controlsX + Self.zoneWidth * (CGFloat(i) + 0.5), y: bounds.midY)
    }

    override func drawContent(_ b: NSRect) {
        let pressedZone = pressPoint.map(zone(at:))
        if pressedZone == .info {
            Draw.roundedRect(NSRect(x: 0, y: 0, width: controlsX, height: b.height), radius: Theme.radius, fill: Theme.pillPressed)
        }
        let textWidth = controlsX - 32 - 6

        switch display {
        case .idle(let id, let running):
            if let icon = MusicApps.icon(id) {
                icon.draw(in: NSRect(x: 7, y: b.midY - 9, width: 18, height: 18), from: .zero, operation: .sourceOver,
                          fraction: running ? 1 : 0.6, respectFlipped: true, hints: nil)
            }
            Draw.line(MusicApps.name(id), Theme.font(11, .semibold), Theme.text, x: 32, y: 3, width: textWidth)
            Draw.line(running ? "Belum ada yang diputar" : "Tertutup · ketuk ▶ untuk buka", Theme.font(9.5),
                      Theme.secondary, x: 32, y: 16, width: textWidth)
            let c = center(0)
            if pressedZone == .toggle { Draw.circle(c, 12.5, Theme.pillPressed) }
            Draw.ring(c, 11.5, width: 1.8, color: Theme.track)
            Draw.symbol("play.fill", size: 10.5, weight: .bold, color: Theme.text, center: NSPoint(x: c.x + 1, y: c.y))

        case .track(let t):
            // Equalizer mini: bergerak saat main, rata saat jeda.
            let time = Animator.now
            for i in 0..<4 {
                let wave = abs(sin(time * (3.1 + Double(i) * 1.3) + Double(i) * 1.7))
                let h: CGFloat = t.playing ? 3 + 11 * CGFloat(wave) : 3
                let r = NSRect(x: 9 + CGFloat(i) * 4.2, y: b.midY + 7 - h, width: 2.6, height: h)
                Draw.roundedRect(r, radius: 1.3, fill: t.tint.withAlphaComponent(t.playing ? 1 : 0.5))
            }

            // Sumber selain Spotify/Music (mis. browser) disebut di baris kedua.
            let showsApp = !AppleScriptMusic.supported.contains(t.bundleID)
            let subtitle = [t.artist, showsApp ? t.appName : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            Draw.line(t.title, Theme.font(11, .semibold), Theme.text, x: 32, y: 3, width: textWidth)
            Draw.line(subtitle, Theme.font(9.5), Theme.secondary, x: 32, y: 16, width: textWidth)

            for (i, zone) in zones.enumerated() {
                let c = center(i)
                if pressedZone == zone { Draw.circle(c, 12.5, Theme.pillPressed) }
                let symbol = zone == .prev ? "backward.fill" : zone == .next ? "forward.fill" : (t.playing ? "pause.fill" : "play.fill")
                Draw.symbol(symbol, size: zone == .toggle ? 10.5 : 9, weight: .bold, color: Theme.text, center: c)
            }

            // Progres lagu sebagai cincin di sekeliling tombol play.
            let frac = t.duration > 0 ? CGFloat(t.livePosition / t.duration) : 0
            let toggle = center(zones.firstIndex(of: .toggle) ?? 0)
            Draw.ring(toggle, 11.5, width: 1.8, color: Theme.track)
            Draw.ring(toggle, 11.5, width: 1.8, color: t.tint, to: frac)
        }
    }
}
