import CoreGraphics

/// Hitungan tata letak dashboard (fungsi murni, mudah diuji).
/// 1. Muat semua: lebar asli, sisa ruang dibagi rata sebagai jarak.
/// 2. Tidak muat: widget yang bisa menyusut dikecilkan sebanding, sampai batas minimumnya.
/// 3. Masih tidak muat: semua di lebar minimum dengan jarak minimum, dan strip bisa digeser.
enum StripLayout {
    struct Plan: Equatable {
        var frames: [(x: CGFloat, width: CGFloat)]
        var contentWidth: CGFloat

        static func == (a: Plan, b: Plan) -> Bool {
            a.contentWidth == b.contentWidth && a.frames.elementsEqual(b.frames) { $0.x == $1.x && $0.width == $1.width }
        }
    }

    static func plan(_ widths: [(natural: CGFloat, min: CGFloat)], available: CGFloat, minGap: CGFloat) -> Plan {
        guard !widths.isEmpty else { return Plan(frames: [], contentWidth: 0) }
        let gaps = CGFloat(widths.count - 1)
        let natural = widths.reduce(0) { $0 + $1.natural }
        var sizes = widths.map(\.natural)
        var gap = minGap

        if natural + minGap * gaps <= available {
            if gaps > 0 { gap = (available - natural) / gaps }
        } else {
            let deficit = natural + minGap * gaps - available
            let room = widths.reduce(0) { $0 + ($1.natural - $1.min) }
            if room > 0 {
                let k = min(1, deficit / room)
                sizes = widths.map { $0.natural - ($0.natural - $0.min) * k }
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
