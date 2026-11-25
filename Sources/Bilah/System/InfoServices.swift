import AppKit
import ApplicationServices
import EventKit

// MARK: - Cuaca (Open-Meteo, gratis tanpa akun)

struct WeatherNow: Equatable {
    var temperature: Double
    var code: Int
    var isDay: Bool

    var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    var label: String {
        switch code {
        case 0: "Cerah"
        case 1, 2: "Cerah berawan"
        case 3: "Berawan"
        case 45, 48: "Berkabut"
        case 51...57: "Gerimis"
        case 61...67: "Hujan"
        case 71...77, 85, 86: "Salju"
        case 80...82: "Hujan deras"
        case 95...99: "Badai petir"
        default: "Berawan"
        }
    }
}

final class WeatherService {
    private(set) var current: WeatherNow?
    private(set) var lastUpdate: Date?
    private var location: CityLocation?
    private var loading = false

    /// Ambil ulang kalau lokasi berubah atau data sudah lebih dari 20 menit.
    func refreshIfNeeded(_ location: CityLocation, done: @escaping () -> Void) {
        let stale = lastUpdate.map { Date().timeIntervalSince($0) > 20 * 60 } ?? true
        guard !loading, stale || location != self.location else { return }
        self.location = location
        loading = true
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", location.latitude)),
            .init(name: "longitude", value: String(format: "%.2f", location.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue("Bilah", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let cur = json?["current"] as? [String: Any]
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                if let t = cur?["temperature_2m"] as? Double, let code = cur?["weather_code"] as? Int {
                    self.current = WeatherNow(temperature: t, code: code, isDay: (cur?["is_day"] as? Int ?? 1) == 1)
                    self.lastUpdate = Date()
                }
                done()
            }
        }.resume()
    }
}

// MARK: - Kalender (EventKit)

final class CalendarService {
    private let store = EKEventStore()
    private(set) var next: EKEvent?
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var denied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in self?.refresh()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Acara berikutnya (atau yang sedang berlangsung) dalam 24 jam, tanpa acara seharian.
    func refresh() {
        guard Self.authorized else { next = nil; onChange?(); return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        next = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .first
        onChange?()
    }

    /// Link rapat (Meet, Zoom, Teams, Webex) dari URL, lokasi, atau catatan acara.
    static func meetingLink(_ event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url.absoluteString) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://[^\s<>"]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"]*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }

    private static func isMeeting(_ s: String) -> Bool {
        ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com"].contains { s.contains($0) }
    }
}

// MARK: - Kecepatan internet

final class NetworkMeter {
    private var last: (rx: UInt64, tx: UInt64, at: TimeInterval)?
    private(set) var download: Double = 0 // byte/detik
    private(set) var upload: Double = 0

    func sample() {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  name.hasPrefix("en") || name.hasPrefix("pdp_ip"),
                  let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            rx += UInt64(data.pointee.ifi_ibytes)
            tx += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date().timeIntervalSince1970
        if let l = last, now > l.at, rx >= l.rx, tx >= l.tx {
            download = Double(rx - l.rx) / (now - l.at)
            upload = Double(tx - l.tx) / (now - l.at)
        }
        last = (rx, tx, now)
    }

    static func format(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1 { return "0 KB/s" }
        if kb < 1000 { return "\(Int(kb.rounded())) KB/s" }
        let mb = kb / 1024
        return mb < 10 ? String(format: "%.1f MB/s", mb).replacingOccurrences(of: ".", with: ",")
                       : "\(Int(mb.rounded())) MB/s"
    }
}

// MARK: - Riwayat clipboard (hanya di memori)

final class ClipboardHistory {
    static let maxItems = 8
    private(set) var items: [String] = []
    private var changeCount = NSPasteboard.general.changeCount

    /// Ambil teks baru dari clipboard. Isi dari pengelola sandi (ConcealedType/TransientType) diabaikan.
    @discardableResult
    func poll() -> Bool {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return false }
        changeCount = pb.changeCount
        let types = pb.types ?? []
        let secret = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" || $0.rawValue == "org.nspasteboard.TransientType" }
        guard !secret, let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count < 20_000 else { return false }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        return true
    }

    /// Salin kembali lalu tempel (⌘V) di aplikasi yang aktif. Tanpa izin Aksesibilitas: hanya disalin.
    func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        changeCount = pb.changeCount
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        guard SystemActions.hasAccessibility else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { SystemShortcuts.keyCombo(9, .maskCommand) }
    }

    func clear() { items.removeAll() }
}

// MARK: - Badge aplikasi (dibaca dari Dock lewat Accessibility)

struct AppBadge: Equatable {
    var name: String
    var label: String
    var url: URL?
}

final class DockBadges {
    private(set) var badges: [AppBadge] = []
    private let queue = DispatchQueue(label: "bilah.badges")
    private var loading = false

    func refresh(_ done: @escaping () -> Void) {
        guard !loading, SystemActions.hasAccessibility,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        loading = true
        queue.async { [weak self] in
            let found = Self.read(pid: dock.processIdentifier)
            DispatchQueue.main.async {
                self?.loading = false
                if self?.badges != found {
                    self?.badges = found
                    done()
                }
            }
        }
    }

    private static func read(pid: pid_t) -> [AppBadge] {
        func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var out: [AppBadge] = []
        for list in (attr(app, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            for item in (attr(list, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                guard let label = attr(item, "AXStatusLabel") as? String, !label.isEmpty else { continue }
                let name = attr(item, kAXTitleAttribute) as? String ?? "?"
                let url = (attr(item, kAXURLAttribute) as? URL) ?? (attr(item, kAXURLAttribute) as? NSURL as URL?)
                out.append(AppBadge(name: name, label: label, url: url))
            }
        }
        return out
    }
}
