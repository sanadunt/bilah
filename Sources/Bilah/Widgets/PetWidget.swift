import AppKit
import Combine
import QuartzCore

/// Satu peliharaan: posisi, arah, dan tingkah yang sedang dijalani.
final class Pet {
    enum Mode: Equatable { case idle, sit, walk, run, sleep, happy, dance }

    var config: PetConfig
    var palette: PetPalette
    /// Posisi 0…1 di sepanjang area main.
    var x: CGFloat
    var facing: CGFloat = 1
    var mode: Mode = .idle
    var modeStart: Double = 0
    var modeEnd: Double = 0
    var target: CGFloat?
    var legPhase: CGFloat = 0
    var nextBlink: Double = 0
    var blinkEnd: Double = 0
    var nameUntil: Double = 0
    var nextParticle: Double = 0

    init(config: PetConfig, x: CGFloat) {
        self.config = config
        palette = PetPalette.of(config)
        self.x = x
    }

    func set(_ mode: Mode, now: Double, for duration: Double) {
        self.mode = mode
        modeStart = now
        modeEnd = now + duration
    }
}

struct PetParticle {
    enum Kind { case heart, z, note, alert }
    var kind: Kind
    var x: CGFloat // 0…1, sama dengan posisi peliharaan
    var born: Double
    var life: Double
    var drift: CGFloat
}

/// Dunia kecil para peliharaan. Satu dunia dipakai bersama oleh Touch Bar dan preview jendela.
final class PetWorld {
    private(set) var pets: [Pet] = []
    private(set) var particles: [PetParticle] = []
    /// Lebar area main (pt) dari view terbesar; dipakai supaya kecepatan jalan terasa sama di lebar berapa pun.
    var span: CGFloat = 160
    var lastInteraction = CACurrentMediaTime()

    static let margin: CGFloat = 20

    func sync(_ configs: [PetConfig]) {
        let old = Dictionary(uniqueKeysWithValues: pets.map { ($0.config.id, $0) })
        pets = configs.enumerated().map { i, config in
            if let pet = old[config.id] {
                pet.config = config
                pet.palette = PetPalette.of(config)
                return pet
            }
            let start = configs.count == 1 ? 0.5 : CGFloat(i) / CGFloat(max(1, configs.count - 1)) * 0.6 + 0.2
            return Pet(config: config, x: start)
        }
    }

    // MARK: Langkah waktu

    func step(now: Double, dt: Double, musicPlaying: Bool, dance: Bool, nightSleep: Bool) {
        let hour = Calendar.current.component(.hour, from: Date())
        let night = nightSleep && (hour >= 23 || hour < 6)
        for pet in pets {
            stepBlink(pet, now: now)
            switch pet.mode {
            case .walk, .run:
                move(pet, now: now, dt: dt)
            case .sleep:
                if now >= pet.nextParticle {
                    spawn(.z, at: pet.x + 0.02 * pet.facing, now: now, life: 2.2)
                    pet.nextParticle = now + 1.3
                }
                // Kalau musik mulai, yang tidur tetap tidur; kalau pagi tiba, bangun pelan-pelan.
                if now >= pet.modeEnd { choose(pet, now: now, music: musicPlaying && dance, night: night) }
            case .dance:
                if now >= pet.nextParticle {
                    spawn(.note, at: pet.x, now: now, life: 1.8)
                    pet.nextParticle = now + 1.6
                }
                if now >= pet.modeEnd || !musicPlaying { choose(pet, now: now, music: musicPlaying && dance, night: night) }
            default:
                if now >= pet.modeEnd { choose(pet, now: now, music: musicPlaying && dance, night: night) }
            }
        }
        particles.removeAll { now - $0.born > $0.life }
    }

    private func stepBlink(_ pet: Pet, now: Double) {
        if now >= pet.nextBlink {
            pet.blinkEnd = now + 0.14
            pet.nextBlink = now + Double.random(in: 2.5...6)
        }
    }

    private func move(_ pet: Pet, now: Double, dt: Double) {
        guard let target = pet.target else { pet.set(.idle, now: now, for: 1.5); return }
        let ptPerSec: CGFloat = pet.mode == .run ? 46 : 17
        let speed = ptPerSec / max(span, 40) * CGFloat(dt)
        let d = target - pet.x
        pet.legPhase += CGFloat(dt) * (pet.mode == .run ? 17 : 9)
        if abs(d) <= speed {
            pet.x = target
            pet.target = nil
            pet.set(.idle, now: now, for: .random(in: 1.2...3))
        } else {
            pet.facing = d > 0 ? 1 : -1
            pet.x += d > 0 ? speed : -speed
        }
    }

    /// Pilih tingkah berikutnya secara acak berbobot, sesuai suasana (musik, malam, bosan).
    private func choose(_ pet: Pet, now: Double, music: Bool, night: Bool) {
        let bored = now - lastInteraction > 120
        // Sesekali anjing mengajak kucing kejar-kejaran.
        if pet.config.species == .dog, !night, Double.random(in: 0...1) < 0.08,
           let cat = pets.first(where: { $0.config.species == .cat && $0.mode != .sleep }) {
            pet.mode = .run
            pet.target = cat.x
            cat.mode = .run
            cat.target = cat.x < 0.5 ? 0.95 : 0.05
            return
        }
        var options: [(Pet.Mode, Double)] = [(.idle, 22), (.sit, 25), (.walk, 34), (.run, 6),
                                             (.sleep, night ? 140 : bored ? 30 : 6)]
        if music { options.append((.dance, 80)) }
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        var mode = Pet.Mode.idle
        for (m, w) in options {
            if roll < w { mode = m; break }
            roll -= w
        }
        switch mode {
        case .walk, .run:
            var target: CGFloat
            repeat { target = .random(in: 0.04...0.96) } while abs(target - pet.x) < 0.15
            pet.target = target
            pet.mode = mode
            pet.modeStart = now
        case .sit: pet.set(.sit, now: now, for: .random(in: 4...9))
        case .sleep: pet.set(.sleep, now: now, for: night ? .random(in: 60...180) : .random(in: 15...40))
        case .dance: pet.set(.dance, now: now, for: .random(in: 6...12))
        default: pet.set(.idle, now: now, for: .random(in: 2...5))
        }
    }

    // MARK: Sentuhan

    /// Ketuk dekat peliharaan = elus (senang, ❤). Ketuk tempat kosong = panggil ke situ.
    func tap(at x: CGFloat, now: Double) {
        lastInteraction = now
        let x = min(1, max(0, x))
        let reach = 16 / max(span, 40)
        if let pet = pets.min(by: { abs($0.x - x) < abs($1.x - x) }), abs(pet.x - x) <= reach {
            if pet.mode == .sleep { spawn(.alert, at: pet.x, now: now, life: 0.9) }
            pet.target = nil
            pet.set(.happy, now: now, for: 1.4)
            pet.nameUntil = now + 2.2
            spawn(.heart, at: pet.x - 0.01, now: now, life: 1.4)
            spawn(.heart, at: pet.x + 0.02, now: now + 0.25, life: 1.4)
        } else if let pet = pets.min(by: { abs($0.x - x) < abs($1.x - x) }) {
            if pet.mode == .sleep { spawn(.alert, at: pet.x, now: now, life: 0.9) }
            pet.target = x
            pet.mode = .run
            pet.modeStart = now
        }
    }

    private func spawn(_ kind: PetParticle.Kind, at x: CGFloat, now: Double, life: Double) {
        particles.append(PetParticle(kind: kind, x: x, born: now, life: life, drift: .random(in: -0.6...0.6)))
    }

    // MARK: Pose untuk digambar

    func pose(_ pet: Pet, now: Double) -> PetPose {
        var pose = PetPose()
        let t = CGFloat(now)
        pose.blink = now < pet.blinkEnd
        pose.breath = sin(t * 1.8 + CGFloat(pet.x) * 9) * 0.35
        switch pet.mode {
        case .idle:
            pose.tail = sin(t * (pet.config.species == .dog ? 6 : 1.6)) * (pet.config.species == .dog ? 0.3 : 0.25)
        case .walk, .run:
            let run = pet.mode == .run
            pose.legPhase = pet.legPhase
            pose.legSwing = run ? 0.6 : 0.42
            pose.bob = -abs(sin(pet.legPhase)) * (run ? 1.6 : 0.6)
            pose.tail = sin(t * 8) * 0.3
        case .sit:
            pose.kind = .sit
            pose.tail = sin(t * (pet.config.species == .dog ? 4 : 1.4)) * 0.3
        case .sleep:
            pose.kind = .sleep
            pose.breath = sin(t * 1.4) * 0.7
            pose.blink = true
        case .happy:
            let p = CGFloat(now - pet.modeStart)
            pose.bob = -abs(sin(p * .pi * 2.2)) * 3.5 * max(0, 1 - p / 1.4)
            pose.tail = sin(t * 20) * 0.6
            pose.happyEyes = true
        case .dance:
            pose.kind = .sit
            pose.bob = -abs(sin(t * 5)) * 2.4
            pose.headTilt = sin(t * 5) * 0.2
            pose.tail = sin(t * 10) * 0.5
            pose.happyEyes = sin(t * 2.5) > 0.3
        }
        return pose
    }
}

// MARK: - Widget

final class PetWidget: Widget {
    let kind = WidgetKind.pet
    private let settings: SettingsStore
    private let music: MusicMonitor
    private let world = PetWorld()
    private let views = ViewSet<PetView>()
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var subscription: AnyCancellable?

    init(settings: SettingsStore, music: MusicMonitor) {
        self.settings = settings
        self.music = music
        world.sync(settings.pets)
        subscription = settings.$pets.sink { [weak self] in self?.world.sync($0) }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var ticksWhenHidden: Bool { false }

    func makeView() -> WidgetView {
        let v = PetView(world: world)
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            self.world.tap(at: v.normalized(p.x), now: CACurrentMediaTime())
        }
        views.add(v)
        return v
    }

    func tick() {}

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        var widest: CGFloat = 0
        views.forEach { widest = max(widest, $0.bounds.width) }
        guard widest > 0 else { return }
        world.span = widest - PetWorld.margin * 2
        world.step(now: now, dt: dt, musicPlaying: music.info?.playing == true, dance: settings.petDance,
                   nightSleep: settings.petNightSleep)
        views.forEach { $0.needsDisplay = true }
    }
}

final class PetView: WidgetView {
    private let world: PetWorld

    init(world: PetWorld) {
        self.world = world
        super.init(width: 200, minWidth: 140, range: 120...600)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var highlightsWhole: Bool { false }

    private var playWidth: CGFloat { max(1, bounds.width - PetWorld.margin * 2) }

    func normalized(_ x: CGFloat) -> CGFloat { (x - PetWorld.margin) / playWidth }
    private func px(_ x: CGFloat) -> CGFloat { PetWorld.margin + x * playWidth }

    override func drawContent(_ b: NSRect) {
        let now = CACurrentMediaTime()
        let ground = b.height - 3.5
        // Yang tidur digambar duluan (di belakang).
        for pet in world.pets.sorted(by: { ($0.mode == .sleep ? 0 : 1) < ($1.mode == .sleep ? 0 : 1) }) {
            PetRenderer.draw(pet.config.species, pet.palette, pose: world.pose(pet, now: now),
                             at: NSPoint(x: px(pet.x), y: ground), facing: pet.facing)
        }
        for p in world.particles {
            let age = CGFloat(now - p.born)
            guard age >= 0 else { continue }
            let k = age / CGFloat(p.life)
            let alpha = max(0, 1 - k)
            let x = px(p.x) + p.drift * age * 6
            switch p.kind {
            case .heart:
                Draw.symbol("heart.fill", size: 7, weight: .bold, color: NSColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: 1),
                            center: NSPoint(x: x, y: 10 - age * 9), alpha: alpha)
            case .z:
                Draw.centered("z", Theme.font(6 + k * 4, .bold), Theme.text.withAlphaComponent(alpha * 0.8),
                              x: x + age * 5, width: 12, centerY: 12 - age * 5, align: .left)
            case .note:
                Draw.symbol("music.note", size: 7.5, weight: .bold, color: Theme.teal, center: NSPoint(x: x + age * 4, y: 9 - age * 7),
                            alpha: alpha)
            case .alert:
                Draw.centered("!", Theme.font(10, .heavy), Theme.amber.withAlphaComponent(alpha), x: x - 6, width: 12,
                              centerY: 5, align: .center)
            }
        }
        // Nama muncul sebentar setelah dielus.
        for pet in world.pets where now < pet.nameUntil {
            let name = pet.config.name.isEmpty ? pet.config.species.title : pet.config.name
            let font = Theme.font(8.5, .bold)
            let w = Draw.width(name, font) + 8
            var x = px(pet.x) + (pet.facing > 0 ? 22 : -22 - w)
            x = min(b.width - w - 2, max(2, x))
            Draw.roundedRect(NSRect(x: x, y: 2, width: w, height: 11), radius: 5.5, fill: NSColor.black.withAlphaComponent(0.55))
            Draw.centered(name, font, Theme.text, x: x, width: w, centerY: 7.5, align: .center)
        }
    }
}
