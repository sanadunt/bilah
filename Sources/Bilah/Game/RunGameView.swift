import AppKit
import QuartzCore

/// Tampilan "Kejar Camilan" di Touch Bar: ketuk = lompat (ketuk lagi di udara = lompat ganda).
final class RunGameView: WidgetView {
    let game: RunGame
    private let species: PetSpecies
    private let palette: PetPalette
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var overAt: Double?
    private var lastPhase = RunGame.Phase.ready
    /// Dipanggil tiap sentuhan, supaya bar tidak menutup sendiri saat sedang main.
    var onInteract: (() -> Void)?

    init(width: CGFloat, pet: PetConfig, best: Int, onRecord: @escaping (Int) -> Void) {
        game = RunGame(width: width, best: best)
        species = pet.species
        palette = PetPalette.of(pet)
        super.init(width: width)
        game.onRecord = onRecord
    }

    required init?(coder: NSCoder) { fatalError() }

    override var highlightsWhole: Bool { false }

    // Jalan 60 fps hanya selama tampil.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        last = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.frame60() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func frame60() {
        let now = CACurrentMediaTime()
        game.step(now - last)
        last = now
        if game.phase == .over, lastPhase != .over { overAt = now }
        lastPhase = game.phase
        needsDisplay = true
    }

    // MARK: Sentuhan

    override func touchesBegan(with event: NSEvent) {
        for _ in event.touches(matching: .began, in: self) { press() }
    }

    override func touchesEnded(with event: NSEvent) { game.release() }
    override func touchesCancelled(with event: NSEvent) { game.release() }
    override func mouseDown(with event: NSEvent) { press() }
    override func mouseUp(with event: NSEvent) { game.release() }

    private func press() {
        onInteract?()
        // Jeda sebentar setelah kalah, supaya ketukan panik tidak langsung memulai ulang.
        if game.phase == .over, let overAt, CACurrentMediaTime() - overAt < 0.7 { return }
        game.press()
    }

    // MARK: Gambar

    override func draw(_ dirtyRect: NSRect) {
        drawContent(bounds)
    }

    override func drawContent(_ b: NSRect) {
        let ground = b.height - 3
        let t = CACurrentMediaTime()
        Draw.roundedRect(b, radius: Theme.radius, fill: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1))
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: b, xRadius: Theme.radius, yRadius: Theme.radius).addClip()
        drawBackground(b, ground: ground)

        for treat in game.treats where !treat.taken { drawTreat(at: NSPoint(x: treat.x, y: ground - treat.altitude - 3)) }
        for o in game.obstacles { drawObstacle(o, ground: ground, time: t) }
        drawPet(ground: ground, time: t)
        NSGraphicsContext.restoreGraphicsState()
        drawHUD(b)
    }

    private func drawBackground(_ b: NSRect, ground: CGFloat) {
        let d = game.distance
        // Bintang (sangat lambat) dan bukit (lambat): kesan jauh.
        for i in 0..<18 {
            let base = CGFloat((i * 137) % 997) / 997 * (b.width + 40)
            let x = (base - d * 0.04).truncatingRemainder(dividingBy: b.width + 40)
            let y = CGFloat((i * 53) % 13) + 2
            Draw.circle(NSPoint(x: x < 0 ? x + b.width + 40 : x, y: y), i % 3 == 0 ? 0.8 : 0.5,
                        NSColor(white: 1, alpha: i % 4 == 0 ? 0.5 : 0.25))
        }
        for i in 0..<5 {
            let span = b.width + 220
            var x = (CGFloat(i) * 260 - d * 0.18).truncatingRemainder(dividingBy: span)
            if x < -110 { x += span }
            let r = NSRect(x: x, y: ground - 9 - CGFloat(i % 2) * 3, width: 200, height: 26)
            NSColor(srgbRed: 0.11, green: 0.13, blue: 0.17, alpha: 1).setFill()
            NSBezierPath(ovalIn: r).fill()
        }
        // Tanah: garis + putus-putus yang ikut bergerak.
        Draw.roundedRect(NSRect(x: 0, y: ground, width: b.width, height: 3), radius: 0, fill: NSColor(srgbRed: 0.14, green: 0.16, blue: 0.2, alpha: 1))
        let offset = d.truncatingRemainder(dividingBy: 16)
        var x = -offset
        while x < b.width {
            Draw.roundedRect(NSRect(x: x, y: ground + 1, width: 6, height: 0.8), radius: 0.4, fill: NSColor(white: 1, alpha: 0.12))
            x += 16
        }
    }

    private func drawPet(ground: CGFloat, time: Double) {
        var pose = PetPose()
        let t = CGFloat(time)
        switch game.phase {
        case .ready:
            pose.kind = .sit
            pose.tail = sin(t * 4) * 0.3
        case .over:
            pose.kind = .sleep
        case .running:
            if game.onGround {
                pose.legPhase = CGFloat(game.time) * (game.speed / 9)
                pose.legSwing = 0.6
                pose.bob = -abs(sin(pose.legPhase)) * 1.4
            } else {
                pose.legPhase = 0.9
                pose.legSwing = 0.5
                pose.happyEyes = true
            }
            pose.tail = sin(t * 14) * 0.4
        }
        PetRenderer.draw(species, palette, pose: pose, at: NSPoint(x: game.petX, y: ground - game.altitude),
                         facing: 1, scale: 0.55, shadowY: ground)
        if game.phase == .over {
            Draw.centered("!", Theme.font(10, .heavy), Theme.amber, x: game.petX - 6, width: 12, centerY: 6, align: .center)
        }
    }

    private func drawObstacle(_ o: RunGame.Obstacle, ground: CGFloat, time: Double) {
        let r = NSRect(x: o.x, y: ground - o.altitude - o.height, width: o.width, height: o.height)
        switch o.kind {
        case .box:
            Draw.roundedRect(r, radius: 1.2, fill: NSColor(srgbRed: 0.74, green: 0.55, blue: 0.34, alpha: 1))
            Draw.roundedRect(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1.6), radius: 0.8,
                             fill: NSColor(srgbRed: 0.86, green: 0.68, blue: 0.45, alpha: 1))
            Draw.roundedRect(NSRect(x: r.midX - 1, y: r.minY, width: 2, height: r.height), radius: 0,
                             fill: NSColor(srgbRed: 0.93, green: 0.84, blue: 0.62, alpha: 0.9))
        case .hydrant:
            let red = NSColor(srgbRed: 0.92, green: 0.27, blue: 0.24, alpha: 1)
            Draw.roundedRect(NSRect(x: r.minX + 1, y: r.minY + 2, width: r.width - 2, height: r.height - 2), radius: 1.2, fill: red)
            Draw.roundedRect(NSRect(x: r.minX, y: r.minY, width: r.width, height: 3), radius: 1.5,
                             fill: NSColor(srgbRed: 0.75, green: 0.18, blue: 0.16, alpha: 1))
            Draw.roundedRect(NSRect(x: r.minX - 1, y: r.midY, width: r.width + 2, height: 2), radius: 1, fill: red)
        case .ball:
            let c = NSPoint(x: r.midX, y: r.midY)
            Draw.circle(c, r.width / 2, NSColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 1))
            // Garis yang berputar: bola terlihat menggelinding.
            let a = -game.distance / (r.width / 2)
            let dx = cos(a) * r.width / 2, dy = sin(a) * r.width / 2
            let line = NSBezierPath()
            line.move(to: NSPoint(x: c.x - dx, y: c.y - dy))
            line.line(to: NSPoint(x: c.x + dx, y: c.y + dy))
            line.lineWidth = 1.4
            NSColor.white.withAlphaComponent(0.9).setStroke()
            line.stroke()
        case .bird:
            let body = NSColor(srgbRed: 0.78, green: 0.82, blue: 0.9, alpha: 1)
            Draw.roundedRect(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: r.height - 1), radius: 2.5, fill: body)
            // Sayap mengepak.
            let flap = CGFloat(sin(time * 22)) * 3.2
            let wing = NSBezierPath()
            wing.move(to: NSPoint(x: r.midX - 2, y: r.midY))
            wing.line(to: NSPoint(x: r.midX + 3, y: r.midY))
            wing.line(to: NSPoint(x: r.midX + 1, y: r.midY - 1 - flap))
            wing.close()
            NSColor(srgbRed: 0.6, green: 0.65, blue: 0.76, alpha: 1).setFill()
            wing.fill()
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: r.minX + 1, y: r.midY - 0.5))
            beak.line(to: NSPoint(x: r.minX - 2, y: r.midY + 0.3))
            beak.line(to: NSPoint(x: r.minX + 1, y: r.midY + 1.2))
            beak.close()
            Theme.amber.setFill()
            beak.fill()
            Draw.circle(NSPoint(x: r.minX + 2.6, y: r.midY - 0.4), 0.6, .black)
        }
    }

    /// Tulang untuk anjing, ikan untuk kucing.
    private func drawTreat(at c: NSPoint) {
        if species == .dog {
            let bone = NSColor(srgbRed: 0.97, green: 0.92, blue: 0.82, alpha: 1)
            Draw.roundedRect(NSRect(x: c.x - 3.5, y: c.y - 1, width: 7, height: 2), radius: 1, fill: bone)
            for dx in [-3.5, 3.5] as [CGFloat] {
                Draw.circle(NSPoint(x: c.x + dx, y: c.y - 1), 1.3, bone)
                Draw.circle(NSPoint(x: c.x + dx, y: c.y + 1), 1.3, bone)
            }
        } else {
            let fish = NSColor(srgbRed: 0.55, green: 0.78, blue: 0.98, alpha: 1)
            NSBezierPath(ovalIn: NSRect(x: c.x - 3.5, y: c.y - 2, width: 6, height: 4)).fill(with: fish)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: c.x + 2, y: c.y))
            tail.line(to: NSPoint(x: c.x + 4.5, y: c.y - 2))
            tail.line(to: NSPoint(x: c.x + 4.5, y: c.y + 2))
            tail.close()
            tail.fill(with: fish)
            Draw.circle(NSPoint(x: c.x - 2, y: c.y - 0.5), 0.5, .black)
        }
    }

    private func drawHUD(_ b: NSRect) {
        switch game.phase {
        case .ready:
            message(b, "Kejar Camilan", "Ketuk untuk mulai · lompati rintangan · burung? jangan lompat!")
        case .over:
            let record = game.newRecord ? "Rekor baru! 🎉" : "Rekor \(game.best)"
            message(b, "Aduh! Skor \(game.score)", "\(record) · ketuk untuk main lagi")
        case .running:
            break
        }
        let score = "\(game.score)"
        Draw.line(score, Theme.mono(12, .bold), Theme.text, x: b.width - 70, y: 2.5, width: 62, align: .right)
        Draw.line("REKOR \(game.best)", Theme.font(7.5, .semibold), Theme.secondary, x: b.width - 90, y: 17.5, width: 82,
                  align: .right)
    }

    private func message(_ b: NSRect, _ title: String, _ subtitle: String) {
        let x = game.petX + 40
        Draw.line(title, Theme.font(11, .bold), Theme.text, x: x, y: 3, width: b.width - x - 100)
        Draw.line(subtitle, Theme.font(9), Theme.secondary, x: x, y: 16, width: b.width - x - 100)
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}
