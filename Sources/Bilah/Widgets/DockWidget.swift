import AppKit

/// Salinan Dock di Touch Bar. Lebar widget menentukan berapa ikon yang muat; kalau tidak muat semua,
/// slot terakhir "+N" berganti ke ikon berikutnya.
final class DockWidget: Widget {
    let kind = WidgetKind.dock
    private let settings: SettingsStore
    private let source = DockSource()
    private let views = ViewSet<DockView>()
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []

    init(settings: SettingsStore) {
        self.settings = settings
        _ = RecentApps.shared
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
        reload()
    }

    func makeView() -> WidgetView {
        let v = DockView(iconSize: settings.dockIconSize)
        v.onTap = { [weak v] p in
            guard let v else { return }
            switch v.hit(p) {
            case .app(let app): AppLauncher.open(url: app.url)
            case .more: v.nextPage()
            case nil: break
            }
        }
        views.add(v)
        push()
        return v
    }

    func tick() {
        ticks += 1
        if ticks % 3 == 0 { reload() }
        push()
    }

    private func reload() { source.refresh { [weak self] in self?.push() } }

    private func push() {
        var apps = source.apps
        switch settings.dockOrder {
        case .dock: break
        case .recent: apps = RecentApps.shared.sorted(apps)
        case .running: apps = apps.filter(\.running)
        case .alphabetical: apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let showRunning = settings.dockShowRunning, showBadges = settings.dockShowBadges
        views.forEach {
            $0.apps = apps
            $0.showRunning = showRunning
            $0.showBadges = showBadges
            $0.needsDisplay = true
        }
    }
}

final class DockView: WidgetView {
    enum Hit { case app(DockApp), more }

    var apps: [DockApp] = [] { didSet { if page * perPage >= max(1, apps.count) { page = 0 } } }
    var showRunning = true
    var showBadges = true
    private let size: DockIconSize
    private var page = 0
    private static var iconCache: [String: NSImage] = [:]

    override var highlightsWhole: Bool { false }

    init(iconSize: DockIconSize) {
        size = iconSize
        super.init(width: 260, minWidth: 140, range: 80...1000)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var slots: Int { max(1, Int((bounds.width - 6) / size.slot)) }

    /// Kalau tidak muat semua, slot terakhir dipakai tombol "+N".
    private var overflow: Bool { apps.count > slots }
    private var perPage: Int { overflow ? max(1, slots - 1) : slots }

    private var visible: [DockApp] {
        let start = min(page * perPage, max(0, apps.count - 1))
        return Array(apps.dropFirst(start).prefix(perPage))
    }

    /// Slot dibagi rata selebar widget (tanpa sisa kosong di kanan); kalau aplikasinya sedikit, kelompoknya di tengah.
    private var slotWidth: CGFloat { (bounds.width - 6) / CGFloat(slots) }
    private var usedSlots: Int { overflow ? slots : max(1, apps.count) }
    private var originX: CGFloat { 3 + (bounds.width - 6 - slotWidth * CGFloat(usedSlots)) / 2 }

    private func slotIndex(_ p: NSPoint) -> Int? {
        let x = p.x - originX
        guard x >= 0 else { return nil }
        let i = Int(x / slotWidth)
        return i < usedSlots ? i : nil
    }

    private func center(_ i: Int) -> NSPoint {
        NSPoint(x: originX + slotWidth * (CGFloat(i) + 0.5), y: bounds.midY - (showRunning ? 1.5 : 0))
    }

    func hit(_ p: NSPoint) -> Hit? {
        guard let i = slotIndex(p) else { return nil }
        if overflow && i == perPage { return .more }
        let shown = visible
        return shown.indices.contains(i) ? .app(shown[i]) : nil
    }

    func nextPage() {
        let pages = Int(ceil(Double(apps.count) / Double(perPage)))
        page = (page + 1) % max(1, pages)
        needsDisplay = true
    }

    private static func icon(_ app: DockApp) -> NSImage {
        if let cached = iconCache[app.url.path] { return cached }
        // Safari dkk. di /Applications adalah symlink: tanpa resolve, ikonnya ikut tanda panah alias.
        let img = NSWorkspace.shared.icon(forFile: app.url.resolvingSymlinksInPath().path)
        iconCache[app.url.path] = img
        return img
    }

    override func drawContent(_ b: NSRect) {
        guard !apps.isEmpty else {
            Draw.symbol("dock.rectangle", size: 11, weight: .medium, color: Theme.faint, center: NSPoint(x: 15, y: b.midY))
            Draw.centered(SystemActions.hasAccessibility ? "Membaca Dock…" : "Ketuk: izin Aksesibilitas", Theme.font(10),
                          Theme.secondary, x: 28, width: b.width - 32, centerY: b.midY)
            return
        }
        let pressed = pressPoint.flatMap(slotIndex)
        for (i, app) in visible.enumerated() {
            let c = center(i)
            if pressed == i { Draw.circle(NSPoint(x: c.x, y: b.midY), size.slot / 2 - 2, Theme.pillPressed) }
            let s = size.icon
            Self.icon(app).draw(in: NSRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s), from: .zero,
                                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if showRunning && app.running {
                Draw.circle(NSPoint(x: c.x, y: b.height - 2.5), 1.3, Theme.text.withAlphaComponent(0.75))
            }
            if showBadges, let badge = app.badge {
                let text = badge.count > 3 ? "99+" : badge
                let font = Theme.font(7, .bold)
                let w = max(10, Draw.width(text, font) + 5)
                let r = NSRect(x: c.x + s / 2 - w + 3, y: 1.5, width: w, height: 10)
                Draw.roundedRect(r, radius: 5, fill: Theme.red)
                Draw.centered(text, font, .white, x: r.minX, width: r.width, centerY: r.midY, align: .center)
            }
        }
        if overflow {
            let c = NSPoint(x: originX + slotWidth * (CGFloat(perPage) + 0.5), y: b.midY)
            if pressed == perPage { Draw.circle(c, size.slot / 2 - 2, Theme.pillPressed) }
            // Sisa setelah halaman ini; di halaman terakhir tombolnya kembali ke awal.
            let rest = apps.count - (page + 1) * perPage
            if rest > 0 {
                Draw.centered("+\(rest)", Theme.font(9.5, .bold), Theme.secondary, x: c.x - slotWidth / 2, width: slotWidth,
                              centerY: c.y, align: .center)
            } else {
                Draw.symbol("arrow.uturn.backward", size: 10, weight: .bold, color: Theme.secondary, center: c)
            }
        }
    }
}
