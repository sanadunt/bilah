import AppKit

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case claude, nowPlaying, system, pomodoro, clock, controls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .nowPlaying: "Musik"
        case .system: "Sistem (CPU, RAM, baterai)"
        case .pomodoro: "Pomodoro"
        case .clock: "Jam"
        case .controls: "Pintasan cepat"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .nowPlaying: "music.note"
        case .system: "cpu"
        case .pomodoro: "timer"
        case .clock: "clock"
        case .controls: "slider.horizontal.3"
        }
    }

    /// Nama pendek untuk label di mode Atur tata letak.
    var shortTitle: String {
        switch self {
        case .claude: "Claude"
        case .nowPlaying: "Musik"
        case .system: "Sistem"
        case .pomodoro: "Pomodoro"
        case .clock: "Jam"
        case .controls: "Pintasan"
        }
    }

    var detail: String {
        switch self {
        case .claude: "Status sesi Claude Code dari hook: lagi kerja, nunggu izin, selesai."
        case .nowPlaying: "Lagu di Spotify atau Music, lengkap dengan tombol putar."
        case .system: "Beban CPU, pemakaian RAM, dan baterai."
        case .pomodoro: "Timer fokus dan istirahat. Ketuk untuk mulai/jeda."
        case .clock: "Jam dan tanggal."
        case .controls: "Tombol favorit yang kamu pin, plus ⋯ untuk semua pintasan."
        }
    }

    var tint: NSColor {
        switch self {
        case .claude: Theme.amber
        case .nowPlaying: Theme.green
        case .system: Theme.teal
        case .pomodoro: Theme.coral
        case .clock: Theme.violet
        case .controls: Theme.secondary
        }
    }

    var identifier: NSTouchBarItem.Identifier { .init("local.bilah.\(rawValue)") }

}

protocol Widget: AnyObject {
    var kind: WidgetKind { get }
    /// Tetap di-tick walau dashboard sedang disembunyikan (status Claude untuk ikon Control Strip, timer Pomodoro).
    var ticksWhenHidden: Bool { get }
    /// Bikin view baru tiap bar dibangun ulang; state tetap di objek widget.
    func makeView() -> WidgetView
    /// Dipanggil tiap detik.
    func tick()
}

extension Widget {
    var ticksWhenHidden: Bool { false }
}

/// Tombol kecil di kiri untuk mengecilkan dashboard kembali ke Touch Bar biasa.
/// Tombol kecil di kiri: "‹" mengecilkan dashboard, "×" menutup slider/panel.
final class CloseView: WidgetView {
    private let symbol: String

    init(symbol: String = "chevron.left") {
        self.symbol = symbol
        super.init(width: 30)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        Draw.symbol(symbol, size: 11, weight: .bold, color: Theme.secondary, center: NSPoint(x: b.midX, y: b.midY))
    }
}

/// Ikon di Control Strip: buka dashboard, plus titik status Claude.
final class TrayView: WidgetView {
    var state: ClaudeState? { didSet { if state != oldValue { needsDisplay = true } } }

    init() { super.init(width: 40) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        Draw.symbol("gauge.with.dots.needle.67percent", size: 14, weight: .medium, color: Theme.text,
                    center: NSPoint(x: b.midX, y: b.midY))
        if let color = state?.color {
            let c = NSPoint(x: b.maxX - 8, y: 7.5)
            Draw.circle(c, 4.5, Theme.pill)
            Draw.circle(c, 3.2, color)
        }
    }
}
