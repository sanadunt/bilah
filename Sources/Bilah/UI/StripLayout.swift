import CoreGraphics

/// Cara memakai sisa ruang saat semua widget muat.
enum SpacingMode: String, CaseIterable, Identifiable {
    /// Widget yang lebarnya bawaan melebar sampai batas maksimal; kalau masih sisa, baru jadi jarak.
    case fill
    /// Sisa ruang dibagi rata sebagai jarak antar-widget.
    case spread
    /// Widget rapat di kiri.
    case packed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "Isi penuh"
        case .spread: "Sebar merata"
        case .packed: "Rapat"
        }
    }
}

/// Hitungan tata letak dashboard (fungsi murni, mudah diuji).
/// 1. Muat semua: pakai sisa ruang sesuai `SpacingMode`.
/// 2. Tidak muat: widget yang bisa menyusut dikecilkan sebanding, sampai batas minimumnya.
/// 3. Masih tidak muat: semua di lebar minimum dengan jarak minimum, dan strip bisa digeser.
enum StripLayout {
    struct Item {
        var natural: CGFloat
        var min: CGFloat
        /// Batas melebar di mode Isi penuh (= natural kalau widget tidak boleh melebar).
        var max: CGFloat

        init(natural: CGFloat, min: CGFloat, max: CGFloat? = nil) {
            self.natural = natural
            self.min = Swift.min(min, natural)
            self.max = Swift.max(max ?? natural, natural)
        }
    }

    struct Plan: Equatable {
        var frames: [(x: CGFloat, width: CGFloat)]
        var contentWidth: CGFloat

        static func == (a: Plan, b: Plan) -> Bool {
            a.contentWidth == b.contentWidth && a.frames.elementsEqual(b.frames) { $0.x == $1.x && $0.width == $1.width }
        }
    }

    static func plan(_ items: [Item], available: CGFloat, minGap: CGFloat, mode: SpacingMode = .fill) -> Plan {
        guard !items.isEmpty else { return Plan(frames: [], contentWidth: 0) }
        let gaps = CGFloat(items.count - 1)
        let natural = items.reduce(0) { $0 + $1.natural }
        var sizes = items.map(\.natural)
        var gap = minGap

        if natural + minGap * gaps <= available {
            var extra = available - natural - minGap * gaps
            if mode == .fill {
                // Bagikan sisa ruang sebanding dengan seberapa jauh tiap widget masih bisa melebar.
                let room = items.reduce(0) { $0 + ($1.max - $1.natural) }
                if room > 0 {
                    let k = min(1, extra / room)
                    sizes = items.map { $0.natural + ($0.max - $0.natural) * k }
                    extra -= room * k
                }
            }
            if mode != .packed, gaps > 0 { gap = minGap + extra / gaps }
        } else {
            let deficit = natural + minGap * gaps - available
            let room = items.reduce(0) { $0 + ($1.natural - $1.min) }
            if room > 0 {
                let k = min(1, deficit / room)
                sizes = items.map { $0.natural - ($0.natural - $0.min) * k }
            }
        }

        var x: CGFloat = 0
        var frames: [(x: CGFloat, width: CGFloat)] = []
        for w in sizes {
            frames.append((x, w))
            x += w + gap
        }
        return Plan(frames: frames, contentWidth: x - gap)
    }
}
