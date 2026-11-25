import AppKit

enum PetSpecies: String, Codable, CaseIterable, Identifiable {
    case dog, cat

    var id: String { rawValue }
    var title: String { self == .dog ? "Anjing" : "Kucing" }
    var variants: [String] {
        self == .dog ? ["Cokelat", "Golden", "Hitam", "Putih"] : ["Oranye", "Abu-abu", "Hitam", "Belang tiga"]
    }
    var defaultName: String { self == .dog ? "Bobo" : "Mochi" }
}

struct PetConfig: Codable, Equatable, Identifiable {
    var id = UUID()
    var species: PetSpecies
    var variant: Int
    var name: String

    static let maxCount = 3
    static var defaults: [PetConfig] {
        [PetConfig(species: .dog, variant: 0, name: "Bobo"), PetConfig(species: .cat, variant: 0, name: "Mochi")]
    }
}

struct PetPalette {
    var body: NSColor
    var dark: NSColor
    var light: NSColor
    var accent: NSColor
    var eye: NSColor
    var stripes = false
    /// Bercak (kucing belang tiga, anjing putih).
    var patch: NSColor?
    var patch2: NSColor?

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func of(_ config: PetConfig) -> PetPalette {
        let v = max(0, min(3, config.variant))
        switch config.species {
        case .dog:
            switch v {
            case 1: return PetPalette(body: c(0.96, 0.76, 0.42), dark: c(0.82, 0.56, 0.26), light: c(1, 0.93, 0.78),
                                      accent: c(0.30, 0.60, 1), eye: c(0.16, 0.10, 0.07))
            case 2: return PetPalette(body: c(0.22, 0.22, 0.24), dark: c(0.12, 0.12, 0.13), light: c(0.62, 0.50, 0.40),
                                      accent: c(1, 0.77, 0.26), eye: c(0.95, 0.90, 0.80))
            case 3: return PetPalette(body: c(0.97, 0.96, 0.93), dark: c(0.58, 0.40, 0.26), light: c(1, 1, 1),
                                      accent: c(0.35, 0.82, 0.80), eye: c(0.16, 0.10, 0.07), patch: c(0.70, 0.50, 0.33))
            default: return PetPalette(body: c(0.74, 0.51, 0.31), dark: c(0.47, 0.29, 0.16), light: c(0.95, 0.85, 0.70),
                                       accent: c(0.93, 0.30, 0.30), eye: c(0.16, 0.10, 0.07))
            }
        case .cat:
            switch v {
            case 1: return PetPalette(body: c(0.64, 0.66, 0.70), dark: c(0.45, 0.47, 0.52), light: c(0.88, 0.89, 0.91),
                                      accent: c(1, 0.62, 0.72), eye: c(1, 0.76, 0.24), stripes: true)
            case 2: return PetPalette(body: c(0.17, 0.17, 0.19), dark: c(0.09, 0.09, 0.10), light: c(0.30, 0.30, 0.33),
                                      accent: c(1, 0.62, 0.72), eye: c(0.70, 0.92, 0.30))
            case 3: return PetPalette(body: c(0.98, 0.97, 0.94), dark: c(0.25, 0.22, 0.20), light: c(1, 1, 1),
                                      accent: c(1, 0.62, 0.72), eye: c(0.45, 0.75, 0.35),
                                      patch: c(0.96, 0.60, 0.25), patch2: c(0.22, 0.20, 0.19))
            default: return PetPalette(body: c(0.99, 0.64, 0.28), dark: c(0.86, 0.45, 0.16), light: c(1, 0.90, 0.76),
                                       accent: c(1, 0.62, 0.72), eye: c(0.40, 0.75, 0.30), stripes: true)
            }
        }
    }
}

/// Pose yang digambar. Angka-angka animasi dihitung oleh PetWorld.
struct PetPose {
    enum Kind { case stand, sit, sleep }
    var kind: Kind = .stand
    /// Fase langkah kaki (radian). 0 = diam.
    var legPhase: CGFloat = 0
    var legSwing: CGFloat = 0
    /// Naik-turun badan (pt, negatif = naik).
    var bob: CGFloat = 0
    var tail: CGFloat = 0
    var headTilt: CGFloat = 0
    var blink = false
    var happyEyes = false
    var breath: CGFloat = 0
}

/// Menggambar anjing/kucing gaya vektor. Koordinat lokal: menghadap kanan, tanah di y = 0, ke atas = negatif.
enum PetRenderer {
    static func draw(_ species: PetSpecies, _ p: PetPalette, pose: PetPose, at ground: NSPoint, facing: CGFloat,
                     scale: CGFloat = 1) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Bayangan di tanah (tidak ikut melompat).
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        let shadowW: CGFloat = (pose.kind == .sleep ? 26 : 24) * scale
        ctx.fillEllipse(in: CGRect(x: ground.x - shadowW / 2, y: ground.y - 1.3 * scale, width: shadowW, height: 2.6 * scale))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: ground.x, y: ground.y + pose.bob * scale)
        ctx.scaleBy(x: facing * scale, y: scale)
        let g = Geo(ctx: ctx)
        switch (species, pose.kind) {
        case (.dog, .stand): dogStand(g, p, pose)
        case (.dog, .sit): dogSit(g, p, pose)
        case (.dog, .sleep): dogSleep(g, p, pose)
        case (.cat, .stand): catStand(g, p, pose)
        case (.cat, .sit): catSit(g, p, pose)
        case (.cat, .sleep): catSleep(g, p, pose)
        }
        ctx.restoreGState()
    }

    // MARK: Anjing

    private static func dogStand(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        // Ekor di belakang badan, mengibas.
        g.capsule(from: CGPoint(x: -10, y: -11.5), angle: -2.2 + pose.tail, length: 8, width: 3, color: p.body)
        // Kaki jauh (lebih gelap) lalu kaki dekat.
        legs(g, xs: [-6.5, 6], top: -7, length: 7, width: 3.1, color: p.dark.blended(withFraction: 0.5, of: p.body) ?? p.dark,
             pose: pose, offset: .pi)
        g.ellipse(CGPoint(x: -1, y: -9.5), w: 23, h: 11.5 + pose.breath, color: p.body)
        if let patch = p.patch { g.ellipse(CGPoint(x: -4, y: -11.5), w: 8, h: 5.5, color: patch) }
        g.ellipse(CGPoint(x: 1, y: -6.3), w: 15, h: 4, color: p.light.withAlphaComponent(0.85))
        legs(g, xs: [-9, 3.5], top: -7, length: 7, width: 3.1, color: p.body, pose: pose, offset: 0)
        // Kalung.
        g.rotated(CGPoint(x: 5.8, y: -12), angle: 0.4) { g.roundRect(CGRect(x: -1.2, y: -3.6, width: 2.4, height: 7.2), r: 1.2, color: p.accent) }
        dogHead(g, p, pose, center: CGPoint(x: 10, y: -16))
    }

    private static func dogSit(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        g.capsule(from: CGPoint(x: -9, y: -2), angle: .pi + 0.25 + pose.tail * 0.5, length: 7, width: 3, color: p.body)
        g.ellipse(CGPoint(x: -4, y: -6), w: 13, h: 11 + pose.breath, color: p.body)
        g.ellipse(CGPoint(x: -6, y: -2), w: 7, h: 4, color: p.dark.blended(withFraction: 0.4, of: p.body) ?? p.dark)
        g.rotated(CGPoint(x: 1.5, y: -11), angle: -0.28) { g.ellipse(.zero, w: 10.5, h: 15, color: p.body) }
        if let patch = p.patch { g.ellipse(CGPoint(x: -3, y: -10), w: 6, h: 5, color: patch) }
        g.ellipse(CGPoint(x: 4, y: -11), w: 5, h: 8, color: p.light)
        g.roundRect(CGRect(x: 2.2, y: -8, width: 3, height: 8), r: 1.5, color: p.body)
        g.roundRect(CGRect(x: 5, y: -8, width: 3, height: 8), r: 1.5, color: p.body)
        g.rotated(CGPoint(x: 3.5, y: -15.5), angle: 0.4) { g.roundRect(CGRect(x: -1.2, y: -3.4, width: 2.4, height: 6.8), r: 1.2, color: p.accent) }
        g.rotated(CGPoint(x: 4.5, y: -15), angle: pose.headTilt) {
            dogHead(g, p, pose, center: CGPoint(x: 1.5, y: -6.5))
        }
    }

    private static func dogSleep(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        g.ellipse(CGPoint(x: -1, y: -5.5), w: 25, h: 11 + pose.breath, color: p.body)
        if let patch = p.patch { g.ellipse(CGPoint(x: -4, y: -7.5), w: 8, h: 5, color: patch) }
        g.capsule(from: CGPoint(x: -12, y: -3), angle: 0.15, length: 15, width: 3.2, color: p.body)
        // Kepala bersandar di tanah, mata terpejam.
        let c = CGPoint(x: 9, y: -5.5)
        g.circle(c, r: 5.6, color: p.body)
        g.ellipse(CGPoint(x: 13.5, y: -3.6), w: 6, h: 4.2, color: p.light)
        g.circle(CGPoint(x: 16.2, y: -4.2), r: 1.1, color: .black)
        g.rotated(CGPoint(x: 6.6, y: -5.2), angle: 1.1) { g.ellipse(.zero, w: 4, h: 7, color: p.dark) }
        g.arc(center: CGPoint(x: 10.5, y: -6.6), r: 1.4, from: 0.2, to: .pi - 0.2, color: p.eye, width: 0.9)
    }

    private static func dogHead(_ g: Geo, _ p: PetPalette, _ pose: PetPose, center c: CGPoint) {
        g.circle(c, r: 6.4, color: p.body)
        g.ellipse(CGPoint(x: c.x + 5, y: c.y + 2.6), w: 7, h: 5, color: p.light)
        g.circle(CGPoint(x: c.x + 8.2, y: c.y + 1.7), r: 1.3, color: .black)
        g.ellipse(CGPoint(x: c.x + 2.6, y: c.y + 2.6), w: 2.4, h: 1.4, color: NSColor(srgbRed: 1, green: 0.5, blue: 0.55, alpha: 0.45))
        // Telinga terkulai.
        g.rotated(CGPoint(x: c.x - 2.6, y: c.y + 1.2), angle: 0.25 + pose.tail * 0.08) {
            g.ellipse(.zero, w: 4.4, h: 8.4, color: p.dark)
        }
        eye(g, p, pose, at: CGPoint(x: c.x + 1.9, y: c.y - 1.2))
    }

    // MARK: Kucing

    private static func catStand(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        catTail(g, p, base: CGPoint(x: -10.5, y: -9.5), sway: pose.tail, up: true)
        legs(g, xs: [-6.5, 5.5], top: -6, length: 6.5, width: 2.6, color: p.dark.blended(withFraction: 0.45, of: p.body) ?? p.dark,
             pose: pose, offset: .pi)
        g.ellipse(CGPoint(x: -1, y: -8.8), w: 21, h: 9.6 + pose.breath, color: p.body)
        if let patch = p.patch { g.ellipse(CGPoint(x: -5, y: -10), w: 7, h: 5, color: patch) }
        if let patch2 = p.patch2 { g.ellipse(CGPoint(x: 3, y: -11), w: 5, h: 3.6, color: patch2) }
        if p.stripes { stripes(g, p, y: -12.6, xs: [-6, -2.5, 1]) }
        g.ellipse(CGPoint(x: 0.5, y: -5.6), w: 13, h: 3.2, color: p.light.withAlphaComponent(0.8))
        legs(g, xs: [-8.5, 3], top: -6, length: 6.5, width: 2.6, color: p.body, pose: pose, offset: 0)
        catHead(g, p, pose, center: CGPoint(x: 10, y: -14))
    }

    private static func catSit(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        // Ekor melingkar di depan kaki.
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: -7, y: -1.6))
        tail.curve(to: CGPoint(x: 7.5, y: -1.2 + pose.tail * 1.5), controlPoint1: CGPoint(x: -3, y: 0.6),
                   controlPoint2: CGPoint(x: 4, y: 0.4))
        g.stroke(tail, color: p.body, width: 2.6)
        g.ellipse(CGPoint(x: -3.5, y: -5.5), w: 12, h: 10 + pose.breath, color: p.body)
        g.rotated(CGPoint(x: 1, y: -10), angle: -0.22) { g.ellipse(.zero, w: 9.5, h: 13.5, color: p.body) }
        if let patch = p.patch { g.ellipse(CGPoint(x: -4.5, y: -7), w: 6, h: 5, color: patch) }
        if let patch2 = p.patch2 { g.ellipse(CGPoint(x: -1, y: -11), w: 4, h: 3.5, color: patch2) }
        if p.stripes { stripes(g, p, y: -8.5, xs: [-6.5, -3]) }
        g.ellipse(CGPoint(x: 3.2, y: -9.5), w: 4.5, h: 7, color: p.light)
        g.roundRect(CGRect(x: 2, y: -7, width: 2.6, height: 7), r: 1.3, color: p.body)
        g.roundRect(CGRect(x: 4.6, y: -7, width: 2.6, height: 7), r: 1.3, color: p.body)
        g.rotated(CGPoint(x: 3.5, y: -14), angle: pose.headTilt) {
            catHead(g, p, pose, center: CGPoint(x: 1, y: -5.5))
        }
    }

    private static func catSleep(_ g: Geo, _ p: PetPalette, _ pose: PetPose) {
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: -11, y: -3))
        tail.curve(to: CGPoint(x: 6, y: -0.9), controlPoint1: CGPoint(x: -14, y: 1.5), controlPoint2: CGPoint(x: 0, y: 1.2))
        g.stroke(tail, color: p.body, width: 2.6)
        g.ellipse(CGPoint(x: -1, y: -5), w: 22, h: 10 + pose.breath, color: p.body)
        if let patch = p.patch { g.ellipse(CGPoint(x: -5, y: -7), w: 7, h: 4.5, color: patch) }
        if let patch2 = p.patch2 { g.ellipse(CGPoint(x: 1, y: -7.5), w: 4.5, h: 3.2, color: patch2) }
        if p.stripes { stripes(g, p, y: -8.4, xs: [-6, -2.5, 1]) }
        let c = CGPoint(x: 8.5, y: -5)
        g.triangle(CGPoint(x: c.x - 3.5, y: c.y - 3.5), CGPoint(x: c.x - 4.5, y: c.y - 8), CGPoint(x: c.x - 0.5, y: c.y - 5), color: p.body)
        g.triangle(CGPoint(x: c.x + 1, y: c.y - 5.2), CGPoint(x: c.x + 3, y: c.y - 9), CGPoint(x: c.x + 4.6, y: c.y - 4), color: p.body)
        g.circle(c, r: 5.3, color: p.body)
        if let patch2 = p.patch2 { g.ellipse(CGPoint(x: c.x - 2, y: c.y - 2.5), w: 4, h: 3, color: patch2) }
        g.arc(center: CGPoint(x: c.x + 2, y: c.y - 0.8), r: 1.4, from: 0.2, to: .pi - 0.2, color: p.dark, width: 0.9)
        g.triangle(CGPoint(x: c.x + 4.6, y: c.y + 1), CGPoint(x: c.x + 5.8, y: c.y + 1), CGPoint(x: c.x + 5.2, y: c.y + 1.9), color: p.accent)
    }

    private static func catHead(_ g: Geo, _ p: PetPalette, _ pose: PetPose, center c: CGPoint) {
        // Telinga runcing (belakang lebih gelap), lalu kepala.
        g.triangle(CGPoint(x: c.x - 4.5, y: c.y - 3), CGPoint(x: c.x - 3.2, y: c.y - 10), CGPoint(x: c.x + 0.2, y: c.y - 5.2), color: p.dark)
        g.triangle(CGPoint(x: c.x + 0.4, y: c.y - 5.4), CGPoint(x: c.x + 3, y: c.y - 10.4), CGPoint(x: c.x + 5.2, y: c.y - 3.6), color: p.body)
        g.triangle(CGPoint(x: c.x + 1.6, y: c.y - 5.6), CGPoint(x: c.x + 3, y: c.y - 8.6), CGPoint(x: c.x + 4.2, y: c.y - 4.6), color: p.accent.withAlphaComponent(0.8))
        g.circle(c, r: 6, color: p.body)
        if let patch = p.patch { g.ellipse(CGPoint(x: c.x - 2.5, y: c.y - 2.5), w: 5, h: 4.5, color: patch) }
        if let patch2 = p.patch2 { g.ellipse(CGPoint(x: c.x + 1.5, y: c.y - 4), w: 3.5, h: 2.5, color: patch2) }
        if p.stripes { stripes(g, p, y: c.y - 5.5, xs: [c.x - 1, c.x + 1.5], length: 2.4) }
        g.ellipse(CGPoint(x: c.x + 3.4, y: c.y + 2.6), w: 5.4, h: 3.6, color: p.light)
        g.triangle(CGPoint(x: c.x + 5, y: c.y + 0.8), CGPoint(x: c.x + 6.6, y: c.y + 0.8), CGPoint(x: c.x + 5.8, y: c.y + 1.9), color: p.accent)
        let whisker = p.light.withAlphaComponent(0.7)
        g.line(CGPoint(x: c.x + 5.5, y: c.y + 2.4), CGPoint(x: c.x + 10, y: c.y + 1.6), color: whisker, width: 0.5)
        g.line(CGPoint(x: c.x + 5.5, y: c.y + 2.9), CGPoint(x: c.x + 10, y: c.y + 3.6), color: whisker, width: 0.5)
        g.ellipse(CGPoint(x: c.x + 1.2, y: c.y + 2.4), w: 2.2, h: 1.3, color: NSColor(srgbRed: 1, green: 0.5, blue: 0.6, alpha: 0.4))
        eye(g, p, pose, at: CGPoint(x: c.x + 2.6, y: c.y - 1), cat: true)
    }

    private static func catTail(_ g: Geo, _ p: PetPalette, base: CGPoint, sway: CGFloat, up: Bool) {
        let tail = NSBezierPath()
        tail.move(to: base)
        tail.curve(to: CGPoint(x: base.x - 4 + sway * 4, y: base.y - 12),
                   controlPoint1: CGPoint(x: base.x - 7, y: base.y - 2),
                   controlPoint2: CGPoint(x: base.x - 8 + sway * 3, y: base.y - 8))
        g.stroke(tail, color: p.body, width: 2.6)
        if p.stripes || p.patch2 != nil {
            g.circle(CGPoint(x: base.x - 4 + sway * 4, y: base.y - 12), r: 1.4, color: p.patch2 ?? p.dark)
        }
    }

    // MARK: Bagian umum

    private static func legs(_ g: Geo, xs: [CGFloat], top: CGFloat, length: CGFloat, width: CGFloat, color: NSColor,
                             pose: PetPose, offset: CGFloat) {
        for (i, x) in xs.enumerated() {
            // Kaki depan dan belakang berlawanan fase.
            let phase = pose.legPhase + offset + (i == 0 ? 0 : .pi)
            let swing = sin(phase) * pose.legSwing
            let lift = max(0, cos(phase)) * pose.legSwing * 1.6
            g.rotated(CGPoint(x: x + width / 2, y: top), angle: swing) {
                g.roundRect(CGRect(x: -width / 2, y: 0, width: width, height: length - lift), r: width / 2, color: color)
            }
        }
    }

    private static func stripes(_ g: Geo, _ p: PetPalette, y: CGFloat, xs: [CGFloat], length: CGFloat = 3) {
        for x in xs {
            g.line(CGPoint(x: x, y: y), CGPoint(x: x + 0.6, y: y + length), color: p.dark, width: 1.3)
        }
    }

    private static func eye(_ g: Geo, _ p: PetPalette, _ pose: PetPose, at c: CGPoint, cat: Bool = false) {
        if pose.happyEyes {
            g.arc(center: CGPoint(x: c.x, y: c.y + 0.6), r: 1.4, from: .pi + 0.3, to: 2 * .pi - 0.3, color: cat ? p.dark : p.eye, width: 1)
        } else if pose.blink {
            g.line(CGPoint(x: c.x - 1.2, y: c.y), CGPoint(x: c.x + 1.2, y: c.y), color: cat ? p.dark : p.eye, width: 0.9)
        } else if cat {
            g.circle(c, r: 1.35, color: p.eye)
            g.ellipse(CGPoint(x: c.x + 0.2, y: c.y), w: 0.7, h: 2, color: .black)
            g.circle(CGPoint(x: c.x + 0.5, y: c.y - 0.5), r: 0.35, color: .white)
        } else {
            g.circle(c, r: 1.25, color: p.eye)
            g.circle(CGPoint(x: c.x + 0.4, y: c.y - 0.45), r: 0.4, color: .white)
        }
    }
}

/// Pembantu menggambar di CGContext (koordinat lokal peliharaan).
private struct Geo {
    let ctx: CGContext

    func ellipse(_ c: CGPoint, w: CGFloat, h: CGFloat, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }

    func circle(_ c: CGPoint, r: CGFloat, color: NSColor) { ellipse(c, w: r * 2, h: r * 2, color: color) }

    func roundRect(_ r: CGRect, r radius: CGFloat, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2),
                           transform: nil))
        ctx.fillPath()
    }

    func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.addLine(to: c)
        ctx.closePath()
        ctx.fillPath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    func arc(center: CGPoint, r: CGFloat, from: CGFloat, to: CGFloat, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: r, startAngle: from, endAngle: to, clockwise: false)
        ctx.strokePath()
    }

    func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    /// Kapsul dari satu titik pangkal ke arah `angle` (dipakai untuk ekor anjing).
    func capsule(from base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, color: NSColor) {
        rotated(base, angle: angle) {
            roundRect(CGRect(x: 0, y: -width / 2, width: length, height: width), r: width / 2, color: color)
        }
    }

    func rotated(_ pivot: CGPoint, angle: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: angle)
        body()
        ctx.restoreGState()
    }
}
