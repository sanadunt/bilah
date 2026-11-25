import AppKit

final class ClockWidget: Widget {
    let kind = WidgetKind.clock
    private let views = ViewSet<ClockView>()

    func makeView() -> WidgetView {
        let v = ClockView()
        views.add(v)
        return v
    }

    func tick() { views.forEach { $0.needsDisplay = true } }
}

final class ClockView: WidgetView {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = format
        return f
    }

    private static let time = formatter("HH.mm")
    private static let day = formatter("EEE")
    private static let date = formatter("d MMM")

    init() { super.init(width: 108, range: 64...170) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        let now = Date()
        let time = Self.time.string(from: now)
        // Sempit: jam saja, di tengah. Lebar: jam di kiri, hari dan tanggal di kanan.
        guard b.width >= 100 else {
            Draw.centered(time, Theme.mono(15, .semibold), Theme.text, x: 0, width: b.width, centerY: b.midY, align: .center)
            return
        }
        let dateX = b.width - 46
        Draw.centered(time, Theme.mono(15, .semibold), Theme.text, x: 9, width: dateX - 12, centerY: b.midY,
                      align: b.width > 130 ? .center : .left)
        Draw.line(Self.day.string(from: now), Theme.font(9, .semibold), Theme.coral, x: dateX, y: 4, width: 42)
        Draw.line(Self.date.string(from: now), Theme.font(9, .medium), Theme.secondary, x: dateX, y: 15.5, width: 42)
    }
}
