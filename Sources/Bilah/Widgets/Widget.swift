import AppKit

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case claude, nowPlaying, system, pomodoro, clock, controls, pet
    case prayer, calendar, weather, network, clipboard, badges

    var id: String { rawValue }

    /// Widget yang sudah ada sebelum v0.12 (aktif bawaan di halaman "Utama").
    static let legacyDefaults: Set<WidgetKind> = [.claude, .nowPlaying, .system, .pomodoro, .clock, .controls, .pet]

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .nowPlaying: "Musik"
        case .system: "Sistem (CPU, RAM, baterai)"
        case .pomodoro: "Pomodoro"
        case .clock: "Jam"
        case .controls: "Pintasan cepat"
        case .pet: "Peliharaan"
        case .prayer: "Jadwal sholat"
        case .calendar: "Rapat berikutnya"
        case .weather: "Cuaca"
        case .network: "Kecepatan internet"
        case .clipboard: "Riwayat clipboard"
        case .badges: "Badge aplikasi"
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
        case .pet: "pawprint.fill"
        case .prayer: "moon.stars.fill"
        case .calendar: "calendar"
        case .weather: "cloud.sun.fill"
        case .network: "arrow.up.arrow.down"
        case .clipboard: "doc.on.clipboard"
        case .badges: "app.badge"
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
        case .pet: "Peliharaan"
        case .prayer: "Sholat"
        case .calendar: "Rapat"
        case .weather: "Cuaca"
        case .network: "Internet"
        case .clipboard: "Clipboard"
        case .badges: "Badge"
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
        case .pet: "Anjing dan kucing yang jalan-jalan, tidur, dan joget. Ketuk untuk mengelus."
        case .prayer: "Waktu sholat berikutnya dan hitung mundurnya (Kemenag, dihitung offline)."
        case .calendar: "Acara berikutnya dari Kalender; ketuk untuk membuka link rapat."
        case .weather: "Suhu dan cuaca sekarang di kotamu (Open-Meteo)."
        case .network: "Kecepatan unduh dan unggah saat ini."
        case .clipboard: "Teks yang baru disalin; ketuk untuk menempelkannya lagi."
        case .badges: "Aplikasi yang punya notifikasi belum dibaca (dari badge di Dock)."
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
        case .pet: NSColor(srgbRed: 1, green: 0.55, blue: 0.65, alpha: 1)
        case .prayer: Theme.green
        case .calendar: Theme.red
        case .weather: Theme.teal
        case .network: Theme.violet
        case .clipboard: Theme.secondary
        case .badges: Theme.red
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

/// Awal dashboard: ‹ (kecilkan) dan, kalau halaman > 1, titik halaman (ketuk = halaman berikutnya).
final class DashboardLeadingView: WidgetView {
    var onCollapse: (() -> Void)?
    var onNextPage: (() -> Void)?
    private let pageCount: Int
    private let current: Int

    init(pageCount: Int, current: Int) {
        self.pageCount = pageCount
        self.current = current
        super.init(width: pageCount > 1 ? 50 : 30)
        onTap = { [weak self] p in
            guard let self else { return }
            if p.x < 30 { self.onCollapse?() } else { self.onNextPage?() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var highlightsWhole: Bool { false }

    override func drawContent(_ b: NSRect) {
        let onChevron = pressPoint.map { $0.x < 30 }
        if onChevron == true { Draw.roundedRect(NSRect(x: 0, y: 0, width: 30, height: b.height), radius: Theme.radius, fill: Theme.pillPressed) }
        Draw.symbol("chevron.left", size: 11, weight: .bold, color: Theme.secondary, center: NSPoint(x: 15, y: b.midY))
        guard pageCount > 1 else { return }
        if onChevron == false {
            Draw.roundedRect(NSRect(x: 30, y: 0, width: b.width - 30, height: b.height), radius: Theme.radius, fill: Theme.pillPressed)
        }
        Draw.roundedRect(NSRect(x: 30, y: 7, width: 1, height: b.height - 14), radius: 0.5, fill: Theme.divider)
        let shown = min(pageCount, 5)
        let step: CGFloat = 5.5
        let y0 = b.midY - step * CGFloat(shown - 1) / 2
        for i in 0..<shown {
            Draw.circle(NSPoint(x: 40, y: y0 + step * CGFloat(i)), i == current ? 2.4 : 1.5,
                        i == current ? Theme.text : Theme.secondary.withAlphaComponent(0.6))
        }
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
