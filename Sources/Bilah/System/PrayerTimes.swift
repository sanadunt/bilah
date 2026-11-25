import Foundation

/// Kota untuk jadwal sholat dan cuaca.
struct CityLocation: Codable, Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double

    static let presets: [CityLocation] = [
        .init(name: "Jakarta", latitude: -6.2088, longitude: 106.8456),
        .init(name: "Bogor", latitude: -6.5950, longitude: 106.8166),
        .init(name: "Depok", latitude: -6.4025, longitude: 106.7942),
        .init(name: "Tangerang", latitude: -6.1783, longitude: 106.6319),
        .init(name: "Bekasi", latitude: -6.2383, longitude: 106.9756),
        .init(name: "Bandung", latitude: -6.9175, longitude: 107.6191),
        .init(name: "Semarang", latitude: -6.9667, longitude: 110.4167),
        .init(name: "Yogyakarta", latitude: -7.7956, longitude: 110.3695),
        .init(name: "Solo", latitude: -7.5755, longitude: 110.8243),
        .init(name: "Surabaya", latitude: -7.2575, longitude: 112.7521),
        .init(name: "Malang", latitude: -7.9666, longitude: 112.6326),
        .init(name: "Denpasar", latitude: -8.6705, longitude: 115.2126),
        .init(name: "Medan", latitude: 3.5952, longitude: 98.6722),
        .init(name: "Padang", latitude: -0.9471, longitude: 100.4172),
        .init(name: "Pekanbaru", latitude: 0.5071, longitude: 101.4478),
        .init(name: "Palembang", latitude: -2.9761, longitude: 104.7754),
        .init(name: "Banda Aceh", latitude: 5.5483, longitude: 95.3238),
        .init(name: "Pontianak", latitude: -0.0263, longitude: 109.3425),
        .init(name: "Balikpapan", latitude: -1.2379, longitude: 116.8529),
        .init(name: "Banjarmasin", latitude: -3.3186, longitude: 114.5944),
        .init(name: "Makassar", latitude: -5.1477, longitude: 119.4327),
        .init(name: "Manado", latitude: 1.4748, longitude: 124.8421),
        .init(name: "Mataram", latitude: -8.5833, longitude: 116.1167),
        .init(name: "Kupang", latitude: -10.1772, longitude: 123.6070),
        .init(name: "Ambon", latitude: -3.6954, longitude: 128.1814),
        .init(name: "Jayapura", latitude: -2.5337, longitude: 140.7181),
    ]
}

/// Jadwal sholat dihitung offline (rumus astronomi standar) dengan parameter Kemenag RI:
/// Subuh 20°, Isya 18°, Ashar mazhab Syafi'i (bayangan 1×), Maghrib saat matahari terbenam,
/// ditambah ihtiyat 2 menit (terbit dikurangi 2 menit).
enum PrayerTimes {
    enum Prayer: String, CaseIterable {
        case fajr = "Subuh", sunrise = "Terbit", dhuhr = "Dzuhur", asr = "Ashar", maghrib = "Maghrib", isha = "Isya"
        /// Terbit bukan waktu sholat; hanya ditampilkan di daftar.
        var isPrayer: Bool { self != .sunrise }
    }

    static let ihtiyatMinutes: Double = 2

    /// Waktu-waktu untuk satu tanggal di zona waktu tertentu.
    static func times(for date: Date, at location: CityLocation, timeZone: TimeZone = .current) -> [(Prayer, Date)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let day = cal.startOfDay(for: date)
        let tz = Double(timeZone.secondsFromGMT(for: day)) / 3600
        let lat = location.latitude, lng = location.longitude

        // Posisi matahari dihitung di siang hari lokal (ketelitian sekitar 1 menit).
        let jd = julianDay(day.addingTimeInterval(12 * 3600))
        let (decl, eqt) = sunPosition(jd)
        let dhuhr = 12 + tz - lng / 15 - eqt

        func hourAngle(_ angle: Double) -> Double {
            let v = (-sin(rad(angle)) - sin(rad(decl)) * sin(rad(lat))) / (cos(rad(decl)) * cos(rad(lat)))
            return deg(acos(min(1, max(-1, v)))) / 15
        }
        let asrAngle = -deg(atan(1 / (1 + tan(rad(abs(lat - decl))))))

        let hours: [(Prayer, Double)] = [
            (.fajr, dhuhr - hourAngle(20) + ihtiyatMinutes / 60),
            (.sunrise, dhuhr - hourAngle(0.833) - ihtiyatMinutes / 60),
            (.dhuhr, dhuhr + ihtiyatMinutes / 60),
            (.asr, dhuhr + hourAngle(asrAngle) + ihtiyatMinutes / 60),
            (.maghrib, dhuhr + hourAngle(0.833) + ihtiyatMinutes / 60),
            (.isha, dhuhr + hourAngle(18) + ihtiyatMinutes / 60),
        ]
        // Dibulatkan ke menit terdekat seperti jadwal cetak.
        return hours.map { ($0.0, day.addingTimeInterval(($0.1 * 60).rounded() * 60)) }
    }

    /// Waktu sholat berikutnya (melewati tengah malam ke Subuh besok kalau perlu).
    static func next(after now: Date, at location: CityLocation, timeZone: TimeZone = .current) -> (Prayer, Date) {
        let today = times(for: now, at: location, timeZone: timeZone).filter { $0.0.isPrayer }
        if let upcoming = today.first(where: { $0.1 > now }) { return upcoming }
        let tomorrow = now.addingTimeInterval(24 * 3600)
        return times(for: tomorrow, at: location, timeZone: timeZone).first { $0.0.isPrayer }!
    }

    /// Waktu sholat yang baru saja masuk (≤ `window` detik yang lalu), untuk tanda "Waktunya …".
    static func current(at now: Date, location: CityLocation, window: TimeInterval = 10 * 60,
                        timeZone: TimeZone = .current) -> Prayer? {
        times(for: now, at: location, timeZone: timeZone)
            .first { $0.0.isPrayer && now >= $0.1 && now.timeIntervalSince($0.1) < window }?.0
    }

    // MARK: Astronomi

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    private static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2_440_587.5 }

    /// Deklinasi matahari (derajat) dan persamaan waktu (jam).
    private static func sunPosition(_ jd: Double) -> (Double, Double) {
        let d = jd - 2_451_545.0
        let g = fixAngle(357.529 + 0.985_600_28 * d)
        let q = fixAngle(280.459 + 0.985_647_36 * d)
        let l = fixAngle(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)))
        let e = 23.439 - 0.000_000_36 * d
        let ra = deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15
        let decl = deg(asin(sin(rad(e)) * sin(rad(l))))
        let eqt = q / 15 - fixHour(ra)
        return (decl, eqt)
    }

    private static func fixAngle(_ a: Double) -> Double { a - 360 * floor(a / 360) }
    private static func fixHour(_ h: Double) -> Double { h - 24 * floor(h / 24) }
}
