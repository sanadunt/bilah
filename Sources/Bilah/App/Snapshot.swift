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
        let barWidth: CGFloat = 1085
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
        music.track = Track(player: .spotify, playing: true, title: "Senja di Kota Tua", artist: "Band Fiktif",
                            position: 132, duration: 245, stamp: CACurrentMediaTime())

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

        let controls = ControlsView(actions: [.builtin(.brightness), .builtin(.volume), .builtin(.screenshot),
                                              .builtin(.notificationCenter)])
        controls.states = demoStates

        // Urutan default + prioritas: kalau kepenuhan, yang prioritasnya paling rendah (jam) hilang duluan.
        var views: [(WidgetView, NSTouchBarItem.Priority)] = [
            (claude, .high), (music, .normal), (system, .normal), (pomodoro, .high), (ClockView(), .low),
            (controls, .normal),
        ]
        let close = CloseView()
        let available = barWidth - close.fixedWidth - 8
        while views.reduce(0, { $0 + $1.0.fixedWidth }) + 6 * CGFloat(views.count - 1) > available,
              let drop = views.indices.min(by: { views[$0].1.rawValue < views[$1].1.rawValue }) {
            views.remove(at: drop)
        }
        layout([close], in: canvas, inset: inset, barWidth: barWidth)
        layout(views.map(\.0), startX: inset + close.fixedWidth + 8, in: canvas, inset: inset, barWidth: barWidth)
        render(canvas, to: path)

        // Mode slider volume.
        let sliderCanvas = Canvas(frame: canvas.frame)
        let slider = SliderView(kind: .volume, width: 900)
        slider.value = 0.45
        layout([CloseView()], in: sliderCanvas, inset: inset, barWidth: barWidth)
        slider.frame = NSRect(x: inset + 30 + 8, y: inset, width: slider.fixedWidth, height: Theme.height)
        sliderCanvas.addSubview(slider)
        let sliderPath = (path as NSString).deletingPathExtension + "-slider.png"
        render(sliderCanvas, to: sliderPath)

        // Panel semua pintasan.
        let panelCanvas = Canvas(frame: canvas.frame)
        layout([CloseView()], in: panelCanvas, inset: inset, barWidth: barWidth)
        let panel = ShortcutPanelView(actions: BuiltinAction.allCases.filter { $0 != .inputSource }.map { .builtin($0) },
                                      width: barWidth - 38)
        panel.states = demoStates
        panel.frame = NSRect(x: inset + 38, y: inset, width: panel.fixedWidth, height: Theme.height)
        panelCanvas.addSubview(panel)
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

    /// Taruh view berurutan; sisa ruang dibagi rata sebagai jarak (meniru flexibleSpace).
    private static func layout(_ views: [WidgetView], startX: CGFloat? = nil,
                               in canvas: NSView, inset: CGFloat, barWidth: CGFloat) {
        let start = startX ?? inset
        let used = views.reduce(0) { $0 + $1.fixedWidth }
        let gap = views.count > 1 ? (inset + barWidth - start - used) / CGFloat(views.count - 1) : 0
        var x = start
        for v in views {
            v.frame = NSRect(x: x, y: inset, width: v.fixedWidth, height: Theme.height)
            canvas.addSubview(v)
            x += v.fixedWidth + gap
        }
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
    static func window(path: String, page: Page) {
        _ = NSApplication.shared
        let store = SettingsStore()
        let dashboard = DashboardController(settings: store)
        let nav = Navigation()
        nav.page = page
        let root = MainView(store: store, dashboard: dashboard, updater: Updater(), navigation: nav)
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
