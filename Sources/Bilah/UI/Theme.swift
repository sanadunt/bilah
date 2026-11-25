import AppKit

enum Theme {
    static let height: CGFloat = 30
    static let radius: CGFloat = 7

    static var pillStyle = PillStyle.gray
    static var accentChoice = AccentChoice.coral

    /// Latar kapsul sesuai tema.
    static var pill: NSColor {
        switch pillStyle {
        case .gray: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1)
        case .black: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        case .outline: NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1)
        }
    }
    static let pillPressed = NSColor(srgbRed: 0.31, green: 0.31, blue: 0.33, alpha: 1)
    static let text = NSColor(white: 0.96, alpha: 1)
    static let secondary = NSColor(white: 0.60, alpha: 1)
    static let faint = NSColor(white: 0.34, alpha: 1)
    static let track = NSColor(white: 1, alpha: 0.12)
    static let divider = NSColor(white: 1, alpha: 0.08)

    /// Warna aksen tema (dipakai Claude "lagi kerja", Pomodoro fokus, hari di Jam, dll).
    static var coral: NSColor { accentChoice.color }
    static let amber = NSColor(srgbRed: 1.00, green: 0.77, blue: 0.26, alpha: 1)
    static let green = NSColor(srgbRed: 0.30, green: 0.85, blue: 0.47, alpha: 1)
    static let red = NSColor(srgbRed: 1.00, green: 0.38, blue: 0.35, alpha: 1)
    static let blue = NSColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
    static let teal = NSColor(srgbRed: 0.38, green: 0.82, blue: 0.93, alpha: 1)
    static let violet = NSColor(srgbRed: 0.68, green: 0.58, blue: 1.00, alpha: 1)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// Warna beban: hijau → kuning → merah.
    static func load(_ value: Double) -> NSColor {
        value > 0.8 ? red : value > 0.55 ? amber : green
    }
}

/// Helper gambar untuk view ber-koordinat flipped (y dari atas).
enum Draw {
    static func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }

    static func width(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Satu baris teks, pojok kiri-atas di (x, y), dipotong "…" kalau kepanjangan.
    static func line(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat, width: CGFloat,
                     align: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = align
        let rect = NSRect(x: x, y: y, width: max(0, width), height: lineHeight(font))
        (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }

    static func centered(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, width: CGFloat, centerY: CGFloat,
                         align: NSTextAlignment = .left) {
        line(s, font, color, x: x, y: centerY - lineHeight(font) / 2, width: width, align: align)
    }

    private static var symbolCache: [String: NSImage] = [:]

    static func symbolImage(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let c = color.usingColorSpace(.sRGB) ?? color
        let key = "\(name)|\(size)|\(weight.rawValue)|\(c.redComponent),\(c.greenComponent),\(c.blueComponent),\(c.alphaComponent)"
        if let cached = symbolCache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return nil }
        let img = NSImage(size: base.size, flipped: false) { r in
            base.draw(in: r)
            c.set()
            r.fill(using: .sourceAtop)
            return true
        }
        symbolCache[key] = img
        return img
    }

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor,
                       center: NSPoint, alpha: CGFloat = 1) {
        guard let img = symbolImage(name, size: size, weight: weight, color: color) else { return }
        let s = img.size
        img.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height),
                 from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
    }

    static func circle(_ center: NSPoint, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()
    }

    /// Busur progres, mulai dari jam 12 searah jarum jam. `from`/`to` dalam 0...1.
    static func ring(_ center: NSPoint, _ r: CGFloat, width: CGFloat, color: NSColor, from: CGFloat = 0, to: CGFloat = 1) {
        let to = min(max(to, 0), 1)
        guard to > from else { return }
        let p = NSBezierPath()
        p.appendArc(withCenter: center, radius: r, startAngle: -90 + 360 * from, endAngle: -90 + 360 * to, clockwise: false)
        p.lineWidth = width
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
    }

    /// Kapsul widget/tombol sesuai tema (gaya "Garis" diberi tepi tipis).
    static func pill(_ rect: NSRect, pressed: Bool = false, radius: CGFloat = Theme.radius) {
        roundedRect(rect, radius: radius, fill: pressed ? Theme.pillPressed : Theme.pill)
        guard Theme.pillStyle == .outline, !pressed else { return }
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        NSColor(white: 1, alpha: 0.22).setStroke()
        border.stroke()
    }

    static func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum PillStyle: String, CaseIterable, Identifiable {
    case gray, black, outline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gray: "Abu-abu"
        case .black: "Hitam"
        case .outline: "Garis"
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case coral, blue, green, purple, pink, yellow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .coral: "Koral"
        case .blue: "Biru"
        case .green: "Hijau"
        case .purple: "Ungu"
        case .pink: "Merah muda"
        case .yellow: "Kuning"
        }
    }
    var color: NSColor {
        switch self {
        case .coral: NSColor(srgbRed: 0.93, green: 0.52, blue: 0.38, alpha: 1)
        case .blue: NSColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
        case .green: NSColor(srgbRed: 0.30, green: 0.82, blue: 0.55, alpha: 1)
        case .purple: NSColor(srgbRed: 0.68, green: 0.55, blue: 1.0, alpha: 1)
        case .pink: NSColor(srgbRed: 1.0, green: 0.50, blue: 0.66, alpha: 1)
        case .yellow: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.28, alpha: 1)
        }
    }
}
