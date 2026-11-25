import AppKit
import QuartzCore
import SwiftUI

/// `Bilah snapshot out.png`: render dashboard dengan data contoh ke PNG (2x), tanpa menyentuh Touch Bar asli.
enum Snapshot {
    private final class Canvas: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 0.11, alpha: 1).setFill()
            bounds.fill()
            Draw.roundedRect(bounds.insetBy(dx: 10, dy: 10), radius: 9, fill: .black)
        }
    }

    static func run(path: String) {
        _ = NSApplication.shared
        let barWidth: CGFloat = 1004 // ruang Touch Bar terukur di MacBook Pro 13" M1
        let inset: CGFloat = 14
        let canvas = Canvas(frame: NSRect(x: 0, y: 0, width: barWidth + inset * 2, height: Theme.height + inset * 2))

        let now = Date().timeIntervalSince1970
        let claude = ClaudeView()
        let sessions = [
            ClaudeSession(id: "a", state: .waiting, project: "bilah", since: now - 40, updated: now - 40),
            ClaudeSession(id: "b", state: .working, project: "game-jam", since: now - 420, updated: now - 5),
            ClaudeSession(id: "c", state: .done, project: "radar", since: now - 900, updated: now - 900),
        ]
        claude.update(sessions: sessions, focusID: "a")

        let music = NowPlayingView()
        music.display = .track(Track(bundleID: MusicApps.spotify, appName: "Spotify", playing: true,
                                     title: "Senja di Kota Tua", artist: "Band Fiktif", position: 132, duration: 245,
                                     stamp: CACurrentMediaTime()))

        let system = SystemView()
        system.cpuHistory = (0..<SystemView.historyLength).map { (i: Int) -> Double in
            let x = Double(i)
            let wave: Double = 0.12 * sin(x / 2.5)
            let spike: Double = i > 26 ? 0.18 * (x - 26) / 9 : 0
            return 0.22 + wave + spike
        }
        system.memory = 0.63
        system.battery = BatteryInfo(percent: 84, charging: true, pluggedIn: true)

        let pomodoro = PomodoroView()
        pomodoro.display = PomodoroDisplay(phase: .focus, state: .running, remaining: 18 * 60 + 42, total: 25 * 60)

        let controls = ControlsView(actions: [.builtin(.brightness), .builtin(.keyboardBrightness), .builtin(.nightShift),
                                              .builtin(.volume), .builtin(.screenshot), .builtin(.notificationCenter)])
        controls.states = demoStates

        // Strip yang sama dengan di Touch Bar: kalau sempit, Claude dan Musik menyusut dulu, lalu bisa digeser.
        let strip = DashboardStripView(widgets: [claude, music, system, pomodoro, ClockView(), controls])
        add(BarContainerView(leading: CloseView(), content: strip, width: barWidth), to: canvas, inset: inset)
        render(canvas, to: path)

        // Peliharaan: anjing jalan, kucing dielus, anjing putih tidur.
        let petCanvas = Canvas(frame: canvas.frame)
        let world = PetWorld()
        world.sync([PetConfig(species: .dog, variant: 0, name: "Bobo"), PetConfig(species: .cat, variant: 0, name: "Mochi"),
                    PetConfig(species: .dog, variant: 3, name: "Kopi")])
        world.span = barWidth - 38 - PetWorld.margin * 2
        let petNow = CACurrentMediaTime()
        world.pets[0].x = 0.18; world.pets[0].mode = .walk; world.pets[0].target = 0.4; world.pets[0].legPhase = 1.1
        world.pets[1].x = 0.55
        world.tap(at: 0.55, now: petNow - 0.35)
        world.pets[2].x = 0.88; world.pets[2].set(.sleep, now: petNow, for: 60); world.pets[2].facing = -1
        world.step(now: petNow, dt: 0.01, musicPlaying: false, dance: true, nightSleep: false)
        let petView = PetView(world: world)
        add(BarContainerView(leading: CloseView(), content: petView, width: barWidth), to: petCanvas, inset: inset)
        render(petCanvas, to: (path as NSString).deletingPathExtension + "-pets.png")

        // Game: jalankan beberapa detik dengan lompat otomatis sampai ada rintangan, camilan, dan lompatan.
        for (suffix, seconds) in [("-game-ready", 0.0), ("-game", 14.0)] {
            let gameCanvas = Canvas(frame: canvas.frame)
            let gameView = RunGameView(width: barWidth - 38, pet: PetConfig.defaults[0], best: 1240) { _ in }
            let g = gameView.game
            if seconds > 0 {
                g.press()
                var t = 0.0
                var captured = false
                while t < seconds + 20 && !captured {
                    let (_, front) = RunGame.hitX(g.petX)
                    if let o = g.obstacles.filter({ $0.kind != .bird && $0.x + $0.width > g.petX - 8 }).min(by: { $0.x < $1.x }),
                       g.onGround, o.x - front <= g.speed * 0.189 - (o.width + 11) / 2 { g.press() }
                    g.step(1.0 / 60)
                    t += 1.0 / 60
                    captured = t > seconds && !g.onGround && g.obstacles.count >= 3 && g.treats.contains { !$0.taken }
                }
            }
            add(BarContainerView(content: gameView, trailing: CloseView(symbol: "xmark"), width: barWidth),
                to: gameCanvas, inset: inset)
            render(gameCanvas, to: (path as NSString).deletingPathExtension + suffix + ".png")
        }

        // Halaman Info: sholat (perhitungan asli), sisanya data contoh (bukan clipboard/notifikasi sungguhan).
        let infoCanvas = Canvas(frame: canvas.frame)
        let prayer = PrayerView()
        prayer.update(next: PrayerTimes.next(after: Date(), at: CityLocation.presets[0]), current: nil)
        let calendarView = CalendarView()
        calendarView.state = .event(title: "Sync mingguan tim", start: Date().addingTimeInterval(12 * 60),
                                    end: Date().addingTimeInterval(42 * 60), color: Theme.blue, hasLink: true)
        let weatherView = WeatherView()
        weatherView.weather = WeatherNow(temperature: 29.4, code: 2, isDay: true)
        weatherView.city = "Jakarta"
        let networkView = NetworkView()
        networkView.down = 1_350_000
        networkView.up = 84_000
        let badgesView = BadgesView()
        badgesView.badges = [AppBadge(name: "Mail", label: "3", url: URL(fileURLWithPath: "/System/Applications/Mail.app")),
                             AppBadge(name: "Messages", label: "12", url: URL(fileURLWithPath: "/System/Applications/Messages.app"))]
        let clipView = ClipboardView()
        clipView.items = ["git push origin main", "Halo, ini contoh teks", "https://example.com"]
        let infoStrip = DashboardStripView(widgets: [prayer, calendarView, weatherView, networkView, badgesView, clipView], mode: .fill)
        add(BarContainerView(leading: DashboardLeadingView(pageCount: 2, current: 1), content: infoStrip, width: barWidth),
            to: infoCanvas, inset: inset)
        render(infoCanvas, to: (path as NSString).deletingPathExtension + "-info.png")

        // Peliharaan di kotak kecil, di samping widget lain.
        let compactCanvas = Canvas(frame: canvas.frame)
        let compactWorld = PetWorld()
        compactWorld.sync(PetConfig.defaults)
        compactWorld.setCompact(true)
        compactWorld.pets[0].set(.sit, now: petNow, for: 60)
        compactWorld.pets[1].set(.sit, now: petNow, for: 60)
        compactWorld.span = 80
        let compactPets = PetView(world: compactWorld, compact: true, count: 2)
        let compactClock = ClockView()
        let compactControls = ControlsView(actions: [.builtin(.brightness), .builtin(.volume), .builtin(.screenshot)])
        compactControls.states = demoStates
        let compactStrip = DashboardStripView(widgets: [compactPets, compactClock, compactControls], mode: .packed)
        add(BarContainerView(leading: CloseView(), content: compactStrip, width: barWidth), to: compactCanvas, inset: inset)
        render(compactCanvas, to: (path as NSString).deletingPathExtension + "-pets-compact.png")

        // Isi penuh: lebih sedikit widget, sisa ruang dipakai untuk melebar (bukan celah kosong).
        let fillCanvas = Canvas(frame: canvas.frame)
        let fillClaude = ClaudeView()
        fillClaude.update(sessions: sessions, focusID: "b")
        let fillMusic = NowPlayingView()
        fillMusic.display = music.display
        let fillControls = ControlsView(actions: [.builtin(.brightness), .builtin(.volume), .builtin(.screenshot),
                                                  .builtin(.notificationCenter)])
        fillControls.states = demoStates
        let fillSystem = SystemView()
        fillSystem.cpuHistory = system.cpuHistory
        fillSystem.memory = system.memory
        fillSystem.battery = system.battery
        let fillStrip = DashboardStripView(widgets: [fillClaude, fillMusic, fillSystem, fillControls], mode: .fill)
        add(BarContainerView(leading: CloseView(), content: fillStrip, width: barWidth), to: fillCanvas, inset: inset)
        render(fillCanvas, to: (path as NSString).deletingPathExtension + "-fill.png")

        // Mode slider volume.
        let sliderCanvas = Canvas(frame: canvas.frame)
        let slider = SliderView(kind: .volume, width: barWidth)
        slider.value = 0.45
        add(BarContainerView(content: slider, width: barWidth), to: sliderCanvas, inset: inset)
        let sliderPath = (path as NSString).deletingPathExtension + "-slider.png"
        render(sliderCanvas, to: sliderPath)

        // Panel semua pintasan.
        let panelCanvas = Canvas(frame: canvas.frame)
        let panel = ShortcutPanelView(actions: BuiltinAction.allCases.filter { $0 != .inputSource }.map { .builtin($0) },
                                      width: barWidth - 38)
        panel.states = demoStates
        add(BarContainerView(content: panel, trailing: CloseView(symbol: "xmark"), width: barWidth),
            to: panelCanvas, inset: inset)
        render(panelCanvas, to: (path as NSString).deletingPathExtension + "-panel.png")
    }

    private static var demoStates: ShortcutStates {
        var s = ShortcutStates()
        s.brightness = 0.62
        s.keyboard = 0.3
        s.volume = 0.45
        s.nightShift = true
        s.keepAwake = true
        return s
    }

    private static func add(_ bar: BarContainerView, to canvas: NSView, inset: CGFloat) {
        bar.frame = NSRect(x: inset, y: inset, width: bar.width, height: Theme.height)
        canvas.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
    }

    private static func render(_ canvas: NSView, to path: String) {
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * scale),
                                         pixelsHigh: Int(canvas.bounds.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Tersimpan: \(path)")
        } catch {
            FileHandle.standardError.write(Data("Gagal menyimpan: \(error)\n".utf8))
        }
    }
}

extension Snapshot {
    /// `Bilah snapshot-window out.png [halaman]`: render jendela utama ke PNG tanpa menampilkannya.
    static func window(path: String, page: Page, editing: Bool = false) {
        _ = NSApplication.shared
        let store = SettingsStore()
        let dashboard = DashboardController(settings: store)
        let nav = Navigation()
        nav.page = page
        let editor = LayoutEditorState()
        editor.editing = editing
        let root = MainView(store: store, dashboard: dashboard, updater: Updater(), navigation: nav, editor: editor)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = host
        w.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Tersimpan: \(path)")
    }
}
