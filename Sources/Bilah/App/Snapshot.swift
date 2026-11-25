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

        let controls = ControlsView(actions: [.builtin(.brightness), .builtin(.keyboardBrightness), .builtin(.nightShift),
                                              .builtin(.volume), .builtin(.screenshot), .builtin(.notificationCenter)])
        controls.states = demoStates

        // Strip yang sama dengan di Touch Bar: kalau sempit, Claude dan Musik menyusut dulu, lalu bisa digeser.
        let strip = DashboardStripView(widgets: [claude, music, system, pomodoro, ClockView(), controls])
        add(BarContainerView(leading: CloseView(), content: strip, width: barWidth), to: canvas, inset: inset)
        render(canvas, to: path)

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
