import CoreGraphics

/// Angka acak yang bisa diulang (untuk uji); xorshift64*.
struct GameRandom {
    private var state: UInt64

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = max(1, seed) }

    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + next() * (r.upperBound - r.lowerBound) }
}

/// "Kejar Camilan": peliharaan lari, lompati rintangan, hindari burung, kumpulkan camilan.
/// Logika murni (tanpa AppKit): koordinat dalam pt, ketinggian dihitung dari tanah ke atas.
final class RunGame {
    enum Phase { case ready, running, over }

    struct Obstacle {
        enum Kind { case box, hydrant, ball, bird }
        var kind: Kind
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        /// Ketinggian bagian bawah dari tanah (0 untuk rintangan di tanah, >0 untuk burung).
        var altitude: CGFloat = 0
    }

    struct Treat {
        var x: CGFloat
        var altitude: CGFloat
        var taken = false
    }

    // Touch Bar cuma 30 pt tingginya: lompatan setinggi ±14,6 pt, dan lompatan ganda "melayang" di batas atas.
    static let gravity: CGFloat = 820
    static let jumpVelocity: CGFloat = 155
    static let doubleJumpVelocity: CGFloat = 120
    static let ceiling: CGFloat = 15
    static let petHeight: CGFloat = 12
    static let petBack: CGFloat = 8
    static let petFront: CGFloat = 9

    let width: CGFloat
    let petX: CGFloat = 70
    private(set) var phase = Phase.ready
    private(set) var altitude: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private(set) var speed: CGFloat = 150
    private(set) var distance: CGFloat = 0
    private(set) var treatsEaten = 0
    private(set) var obstacles: [Obstacle] = []
    private(set) var treats: [Treat] = []
    private(set) var time: Double = 0
    private(set) var best: Int
    private(set) var newRecord = false
    var onRecord: ((Int) -> Void)?

    private var jumpsLeft = 2
    private var nextSpawnAt: CGFloat = 0
    private var rng: GameRandom

    var score: Int { Int(distance / 10) + treatsEaten * 10 }
    var onGround: Bool { altitude <= 0 }

    init(width: CGFloat, best: Int = 0, seed: UInt64? = nil) {
        self.width = width
        self.best = best
        rng = seed.map { GameRandom(seed: $0) } ?? GameRandom()
    }

    // MARK: Masukan

    /// Ketuk: mulai (di layar awal/kalah) atau lompat. Di udara masih bisa sekali lompat lagi.
    func press() {
        switch phase {
        case .ready, .over: start()
        case .running:
            guard jumpsLeft > 0 else { return }
            velocity = jumpsLeft == 2 ? Self.jumpVelocity : Self.doubleJumpVelocity
            jumpsLeft -= 1
        }
    }

    /// Lepas lebih cepat = lompatan lebih pendek.
    func release() {
        if phase == .running, velocity > 0 { velocity *= 0.45 }
    }

    private func start() {
        phase = .running
        altitude = 0
        velocity = 0
        speed = 150
        distance = 0
        treatsEaten = 0
        obstacles = []
        treats = []
        time = 0
        jumpsLeft = 2
        newRecord = false
        nextSpawnAt = width * 0.6
    }

    // MARK: Langkah

    func step(_ dt: Double) {
        guard phase == .running else { return }
        let dt = CGFloat(min(dt, 1.0 / 20))
        time += Double(dt)
        speed = min(340, 150 + distance * 0.016)
        distance += speed * dt

        // Fisika lompat.
        velocity -= Self.gravity * dt
        altitude += velocity * dt
        if altitude <= 0 {
            altitude = 0
            velocity = 0
            jumpsLeft = 2
        } else if altitude > Self.ceiling {
            altitude = Self.ceiling
            velocity = min(velocity, 0)
        }

        // Geser dunia ke kiri. (Bola hanya terlihat menggelinding; kalau lebih cepat, dia menyusul rintangan lain.)
        for i in obstacles.indices { obstacles[i].x -= speed * dt }
        for i in treats.indices { treats[i].x -= speed * dt }
        obstacles.removeAll { $0.x + $0.width < -20 }
        treats.removeAll { $0.x < -20 || $0.taken }

        spawnIfNeeded()
        collide()
    }

    private var spawnX: CGFloat { width + 20 }

    private func spawnIfNeeded() {
        guard distance >= nextSpawnAt else { return }
        let roll = rng.next()
        var kinds: [(Obstacle.Kind, Double)] = [(.box, 40), (.hydrant, 28)]
        if score > 80 { kinds.append((.ball, 16)) }
        if score > 200 { kinds.append((.bird, 22)) }
        let total = kinds.reduce(0) { $0 + $1.1 }
        var pick = roll * total
        var kind = Obstacle.Kind.box
        for (k, w) in kinds {
            if pick < w { kind = k; break }
            pick -= w
        }
        switch kind {
        case .box:
            let big = rng.next() < 0.35
            obstacles.append(Obstacle(kind: .box, x: spawnX, width: big ? 12 : 9, height: big ? 8 : 6))
        case .hydrant:
            obstacles.append(Obstacle(kind: .hydrant, x: spawnX, width: 6, height: 9))
        case .ball:
            obstacles.append(Obstacle(kind: .ball, x: spawnX, width: 7, height: 7))
        case .bird:
            // Lewat di atas peliharaan yang berdiri; menabrak kalau peliharaan melompat.
            obstacles.append(Obstacle(kind: .bird, x: spawnX, width: 11, height: 5, altitude: 14))
        }
        // Camilan di sela rintangan, kadang di udara (harus dilompati).
        if rng.next() < 0.55 {
            let alt: CGFloat = rng.next() < 0.5 ? 2 : CGFloat(rng.range(8...15))
            treats.append(Treat(x: spawnX + CGFloat(rng.range(45...90)), altitude: alt))
        }
        // Jarak antar-rintangan dalam waktu, supaya tetap bisa dilompati walau makin cepat.
        let gapSeconds = rng.range(0.85...1.6) * (kind == .bird ? 1.25 : 1)
        nextSpawnAt = distance + speed * CGFloat(gapSeconds)
    }

    private func collide() {
        // Kotak tabrak peliharaan dikecilkan (kaki, ekor, telinga tidak dihitung) supaya terasa adil.
        let (px0, px1) = Self.hitX(petX)
        let py0 = altitude + 2, py1 = altitude + Self.petHeight - 1
        for o in obstacles {
            let hitX = o.x < px1 && o.x + o.width > px0
            let hitY = o.altitude < py1 && o.altitude + o.height > py0
            if hitX && hitY {
                gameOver()
                return
            }
        }
        for i in treats.indices where !treats[i].taken {
            let t = treats[i]
            if abs(t.x - petX) < 9 && t.altitude + 4 > py0 && t.altitude < py1 + 2 {
                treats[i].taken = true
                treatsEaten += 1
            }
        }
    }

    static func hitX(_ petX: CGFloat) -> (CGFloat, CGFloat) { (petX - petBack + 3, petX + petFront - 3) }

    private func gameOver() {
        phase = .over
        if score > best {
            best = score
            newRecord = true
            onRecord?(best)
        }
    }
}
