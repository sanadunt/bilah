import AppKit
import EventKit

// MARK: - Jadwal sholat

final class PrayerWidget: Widget {
    let kind = WidgetKind.prayer
    private let settings: SettingsStore
    private let views = ViewSet<PrayerView>()

    init(settings: SettingsStore) { self.settings = settings }

    func makeView() -> WidgetView {
        let v = PrayerView()
        views.add(v)
        tick()
        return v
    }

    func tick() {
        let now = Date()
        let next = PrayerTimes.next(after: now, at: settings.location)
        let current = PrayerTimes.current(at: now, location: settings.location)
        views.forEach { $0.update(next: next, current: current) }
    }
}

final class PrayerView: WidgetView {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH.mm"
        return f
    }()
    private var next: (PrayerTimes.Prayer, Date)?
    private var current: PrayerTimes.Prayer?

    init() { super.init(width: 150, minWidth: 120, range: 110...240) }
    required init?(coder: NSCoder) { fatalError() }

    func update(next: (PrayerTimes.Prayer, Date), current: PrayerTimes.Prayer?) {
        self.next = next
        self.current = current
        animating = current != nil
        needsDisplay = true
    }

    override func drawContent(_ b: NSRect) {
        guard let (prayer, time) = next else { return }
        let left = time.timeIntervalSinceNow
        let soon = left < 15 * 60
        let icon = NSPoint(x: 16, y: b.midY)
        if let current {
            // Baru masuk waktunya: kapsul berdenyut lembut.
            let a = 0.12 + 0.12 * CGFloat((sin(Animator.now * 3) + 1) / 2)
            Draw.roundedRect(b, radius: Theme.radius, fill: Theme.amber.withAlphaComponent(a))
            Draw.symbol("moon.stars.fill", size: 12, weight: .semibold, color: Theme.amber, center: icon)
            Draw.line("Waktunya \(current.rawValue)", Theme.font(11, .semibold), Theme.amber, x: 30, y: 3, width: b.width - 36)
            Draw.line("Berikutnya \(prayer.rawValue) \(Self.time.string(from: time))", Theme.font(9.5), Theme.secondary,
                      x: 30, y: 16, width: b.width - 36)
            return
        }
        Draw.symbol("moon.stars.fill", size: 12, weight: .semibold, color: soon ? Theme.amber : Theme.coral, center: icon)
        Draw.line("\(prayer.rawValue) \(Self.time.string(from: time))", Theme.font(11, .semibold), Theme.text,
                  x: 30, y: 3, width: b.width - 36)
        let mins = Int((left / 60).rounded(.up))
        let countdown = mins >= 60 ? "\(mins / 60) j \(mins % 60) mnt lagi" : "\(mins) mnt lagi"
        Draw.line(countdown, Theme.font(9.5, soon ? .semibold : .regular), soon ? Theme.amber : Theme.secondary,
                  x: 30, y: 16, width: b.width - 36)
    }
}

// MARK: - Cuaca

final class WeatherWidget: Widget {
    let kind = WidgetKind.weather
    private let settings: SettingsStore
    private let service = WeatherService()
    private let views = ViewSet<WeatherView>()

    init(settings: SettingsStore) { self.settings = settings }

    func makeView() -> WidgetView {
        let v = WeatherView()
        v.onTap = { _ in
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
        views.add(v)
        tick()
        return v
    }

    func tick() {
        service.refreshIfNeeded(settings.location) { [weak self] in self?.push() }
        push()
    }

    private func push() {
        let w = service.current, city = settings.location.name
        views.forEach {
            $0.weather = w
            $0.city = city
            $0.needsDisplay = true
        }
    }
}

final class WeatherView: WidgetView {
    var weather: WeatherNow?
    var city = ""

    init() { super.init(width: 120, minWidth: 96, range: 70...220) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        guard let w = weather else {
            Draw.symbol("cloud.fill", size: 12, weight: .medium, color: Theme.faint, center: NSPoint(x: 16, y: b.midY))
            Draw.centered("–°", Theme.mono(13, .semibold), Theme.secondary, x: 30, width: b.width - 34, centerY: b.midY)
            return
        }
        let color: NSColor = w.code == 0 ? (w.isDay ? Theme.amber : Theme.violet) : (w.code >= 51 ? Theme.teal : Theme.secondary)
        Draw.symbol(w.symbol, size: 13, weight: .medium, color: color, center: NSPoint(x: 16, y: b.midY))
        let temp = "\(Int(w.temperature.rounded()))°"
        if b.width < 96 {
            Draw.centered(temp, Theme.mono(14, .semibold), Theme.text, x: 30, width: b.width - 32, centerY: b.midY)
            return
        }
        Draw.line(temp, Theme.mono(12, .semibold), Theme.text, x: 31, y: 2.5, width: b.width - 36)
        Draw.line("\(w.label) · \(city)", Theme.font(9), Theme.secondary, x: 31, y: 16.5, width: b.width - 36)
    }
}

// MARK: - Rapat berikutnya

final class CalendarWidget: Widget {
    let kind = WidgetKind.calendar
    private let service = CalendarService()
    private let views = ViewSet<CalendarView>()
    private var ticks = 0

    init() {
        service.onChange = { [weak self] in self?.push() }
        if CalendarService.authorized { service.refresh() }
    }

    func makeView() -> WidgetView {
        let v = CalendarView()
        v.onTap = { [weak self] _ in self?.tap() }
        views.add(v)
        push()
        return v
    }

    func tick() {
        ticks += 1
        if ticks % 30 == 0 { service.refresh() }
        push()
    }

    private func tap() {
        if !CalendarService.authorized {
            if CalendarService.denied {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } else {
                service.requestAccess()
            }
            return
        }
        if let event = service.next, let link = CalendarService.meetingLink(event) {
            NSWorkspace.shared.open(link)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func push() {
        let state: CalendarView.State
        if !CalendarService.authorized {
            state = CalendarService.denied ? .denied : .noAccess
        } else if let e = service.next {
            state = .event(title: e.title ?? "(tanpa judul)", start: e.startDate, end: e.endDate,
                           color: e.calendar?.color ?? Theme.coral, hasLink: CalendarService.meetingLink(e) != nil)
        } else {
            state = .empty
        }
        views.forEach { $0.state = state }
    }
}

final class CalendarView: WidgetView {
    enum State: Equatable {
        case noAccess, denied, empty
        case event(title: String, start: Date, end: Date, color: NSColor, hasLink: Bool)
    }

    var state = State.noAccess { didSet { needsDisplay = true } }
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH.mm"
        return f
    }()

    init() { super.init(width: 190, minWidth: 150, range: 130...360) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        let icon = NSPoint(x: 16, y: b.midY)
        let w = b.width - 36
        switch state {
        case .noAccess, .denied:
            Draw.symbol("calendar.badge.exclamationmark", size: 12, weight: .medium, color: Theme.amber, center: icon)
            Draw.line("Kalender", Theme.font(11, .semibold), Theme.text, x: 30, y: 3, width: w)
            Draw.line(state == .denied ? "Izinkan di Pengaturan Sistem" : "Ketuk untuk mengizinkan", Theme.font(9.5),
                      Theme.secondary, x: 30, y: 16, width: w)
        case .empty:
            Draw.symbol("calendar", size: 12, weight: .medium, color: Theme.faint, center: icon)
            Draw.line("Tidak ada rapat", Theme.font(11, .semibold), Theme.secondary, x: 30, y: 3, width: w)
            Draw.line("24 jam ke depan kosong", Theme.font(9.5), Theme.faint, x: 30, y: 16, width: w)
        case .event(let title, let start, let end, let color, let hasLink):
            let now = Date()
            let ongoing = start <= now
            let mins = Int(((ongoing ? end : start).timeIntervalSince(now) / 60).rounded(.up))
            let soon = !ongoing && mins <= 10
            Draw.circle(icon, 5, color)
            if ongoing { Draw.circle(icon, 2, Theme.pill) }
            let textW = w - (hasLink ? 18 : 0)
            Draw.line(title, Theme.font(11, .semibold), Theme.text, x: 30, y: 3, width: textW)
            let when: String
            if ongoing {
                when = "Sedang berlangsung · sisa \(Self.duration(mins))"
            } else if mins <= 60 {
                when = "dalam \(Self.duration(mins)) · \(Self.time.string(from: start))"
            } else {
                when = (Calendar.current.isDateInToday(start) ? "Hari ini " : "Besok ") + Self.time.string(from: start)
            }
            Draw.line(when, Theme.font(9.5, soon ? .semibold : .regular), soon ? Theme.amber : Theme.secondary,
                      x: 30, y: 16, width: textW)
            if hasLink {
                Draw.symbol("video.fill", size: 10, weight: .semibold, color: Theme.green, center: NSPoint(x: b.width - 14, y: b.midY))
            }
        }
    }

    private static func duration(_ mins: Int) -> String {
        mins >= 60 ? "\(mins / 60) j \(mins % 60) mnt" : "\(max(0, mins)) mnt"
    }
}

// MARK: - Kecepatan internet

final class NetworkWidget: Widget {
    let kind = WidgetKind.network
    private let meter = NetworkMeter()
    private let views = ViewSet<NetworkView>()

    func makeView() -> WidgetView {
        let v = NetworkView()
        views.add(v)
        return v
    }

    func tick() {
        meter.sample()
        let down = meter.download, up = meter.upload
        views.forEach {
            $0.down = down
            $0.up = up
            $0.needsDisplay = true
        }
    }
}

final class NetworkView: WidgetView {
    var down: Double = 0
    var up: Double = 0

    init() { super.init(width: 96, range: 80...170) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        let font = Theme.mono(10, .semibold)
        Draw.symbol("arrow.down", size: 8.5, weight: .bold, color: Theme.teal, center: NSPoint(x: 12, y: 9))
        Draw.line(NetworkMeter.format(down), font, Theme.text, x: 20, y: 2.5, width: b.width - 24)
        Draw.symbol("arrow.up", size: 8.5, weight: .bold, color: Theme.violet, center: NSPoint(x: 12, y: 21))
        Draw.line(NetworkMeter.format(up), font, Theme.secondary, x: 20, y: 15, width: b.width - 24)
    }
}

// MARK: - Riwayat clipboard

final class ClipboardWidget: Widget {
    let kind = WidgetKind.clipboard
    let history = ClipboardHistory()
    private let views = ViewSet<ClipboardView>()
    private var timer: Timer?

    init() {
        // Dipantau terus (ringan), supaya riwayat tetap terkumpul walau widget sedang tidak tampil.
        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            if self?.history.poll() == true { self?.push() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func makeView() -> WidgetView {
        let v = ClipboardView()
        v.onTap = { [weak self, weak v] p in
            guard let self, let v, let text = v.item(at: p) else { return }
            self.history.paste(text)
            self.push()
        }
        views.add(v)
        push()
        return v
    }

    func tick() {}

    func push() {
        let items = history.items
        views.forEach { $0.items = items }
    }
}

final class ClipboardView: WidgetView {
    var items: [String] = [] { didSet { needsDisplay = true } }
    override var highlightsWhole: Bool { false }

    init() { super.init(width: 230, minWidth: 160, range: 120...600) }
    required init?(coder: NSCoder) { fatalError() }

    private static func label(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "\t", with: " ")
    }

    private var chips: [(text: String, rect: NSRect)] {
        var x: CGFloat = 4
        var out: [(String, NSRect)] = []
        let font = Theme.font(10, .medium)
        for item in items {
            let w = min(150, Draw.width(Self.label(item), font) + 16)
            guard x + min(w, 50) <= bounds.width - 4 else { break }
            let width = min(w, bounds.width - 4 - x)
            out.append((item, NSRect(x: x, y: 4, width: width, height: bounds.height - 8)))
            x += width + 4
        }
        return out.map { (text: $0.0, rect: $0.1) }
    }

    func item(at p: NSPoint) -> String? { chips.first { $0.rect.contains(p) }?.text }

    override func drawContent(_ b: NSRect) {
        guard !items.isEmpty else {
            Draw.symbol("doc.on.clipboard", size: 11, weight: .medium, color: Theme.faint, center: NSPoint(x: 15, y: b.midY))
            Draw.centered("Salin sesuatu, nanti muncul di sini", Theme.font(10), Theme.secondary, x: 28, width: b.width - 32,
                          centerY: b.midY)
            return
        }
        let pressed = pressPoint.flatMap { p in chips.first { $0.rect.contains(p) }?.text }
        for chip in chips {
            Draw.roundedRect(chip.rect, radius: 5, fill: pressed == chip.text ? Theme.pillPressed : NSColor(white: 1, alpha: 0.08))
            Draw.centered(Self.label(chip.text), Theme.font(10, .medium), Theme.text, x: chip.rect.minX + 8,
                          width: chip.rect.width - 16, centerY: chip.rect.midY)
        }
    }
}

// MARK: - Badge aplikasi

final class BadgesWidget: Widget {
    let kind = WidgetKind.badges
    private let dock = DockBadges()
    private let views = ViewSet<BadgesView>()
    private var ticks = 0

    func makeView() -> WidgetView {
        let v = BadgesView()
        v.onTap = { [weak v] p in
            guard let v else { return }
            if !SystemActions.hasAccessibility {
                SystemActions.requestAccessibility()
            } else if let url = v.badge(at: p)?.url {
                NSWorkspace.shared.open(url)
            }
        }
        views.add(v)
        push()
        return v
    }

    func tick() {
        if ticks % 3 == 0 { dock.refresh { [weak self] in self?.push() } }
        ticks += 1
        push()
    }

    private func push() {
        let badges = dock.badges, allowed = SystemActions.hasAccessibility
        views.forEach {
            $0.badges = badges
            $0.allowed = allowed
            $0.needsDisplay = true
        }
    }
}

final class BadgesView: WidgetView {
    var badges: [AppBadge] = []
    var allowed = true
    private static let slot: CGFloat = 32
    override var highlightsWhole: Bool { false }

    init() { super.init(width: 150, minWidth: 100, range: 60...400) }
    required init?(coder: NSCoder) { fatalError() }

    private var shown: [AppBadge] { Array(badges.prefix(max(0, Int((bounds.width - 6) / Self.slot)))) }

    func badge(at p: NSPoint) -> AppBadge? {
        let i = Int((p.x - 3) / Self.slot)
        return shown.indices.contains(i) ? shown[i] : nil
    }

    override func drawContent(_ b: NSRect) {
        guard allowed else {
            Draw.symbol("app.badge", size: 11, weight: .medium, color: Theme.amber, center: NSPoint(x: 15, y: b.midY))
            Draw.centered("Ketuk: izin Aksesibilitas", Theme.font(9.5), Theme.secondary, x: 28, width: b.width - 32, centerY: b.midY)
            return
        }
        guard !badges.isEmpty else {
            Draw.symbol("bell.slash", size: 11, weight: .medium, color: Theme.faint, center: NSPoint(x: 15, y: b.midY))
            Draw.centered("Tidak ada notifikasi", Theme.font(10), Theme.secondary, x: 28, width: b.width - 32, centerY: b.midY)
            return
        }
        let pressed = pressPoint.flatMap(badge(at:))
        for (i, badge) in shown.enumerated() {
            let c = NSPoint(x: 3 + Self.slot * (CGFloat(i) + 0.5), y: b.midY)
            if pressed == badge { Draw.circle(c, 14, Theme.pillPressed) }
            if let url = badge.url {
                NSWorkspace.shared.icon(forFile: url.path).draw(in: NSRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20),
                                                                from: .zero, operation: .sourceOver, fraction: 1,
                                                                respectFlipped: true, hints: nil)
            }
            // Gelembung merah berisi angka (atau titik).
            let text = badge.label.count > 3 ? "99+" : badge.label
            let font = Theme.font(7.5, .bold)
            let w = max(11, Draw.width(text, font) + 6)
            let bubble = NSRect(x: c.x + 4, y: 2, width: w, height: 11)
            Draw.roundedRect(bubble, radius: 5.5, fill: Theme.red)
            Draw.centered(text, font, .white, x: bubble.minX, width: bubble.width, centerY: bubble.midY, align: .center)
        }
    }
}
