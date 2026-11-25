import AppKit
import ApplicationServices

/// Membuka/memunculkan aplikasi lain dari Bilah.
/// Sejak macOS 14 (cooperative activation), `NSRunningApplication.activate()` dari aplikasi latar seperti Bilah
/// ditolak diam-diam. `NSWorkspace.openApplication` tetap boleh: aplikasi yang jalan dimunculkan, yang tertutup dibuka.
enum AppLauncher {
    static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        open(url: url)
    }

    static func open(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Untuk proses yang diketahui pid-nya (mis. terminal tempat sesi Claude berjalan).
    static func open(pid: pid_t, fallbackBundleID: String?) {
        if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, let url = app.bundleURL {
            open(url: url)
        } else if let id = fallbackBundleID {
            open(bundleID: id)
        }
    }
}

/// Satu aplikasi di salinan Dock.
struct DockApp: Equatable {
    var bundleID: String?
    var name: String
    var url: URL
    var running: Bool
    var badge: String?

    var key: String { bundleID ?? url.path }
}

/// Urutan widget Dock.
enum DockOrder: String, CaseIterable, Identifiable {
    case dock, recent, running, alphabetical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: "Sesuai Dock"
        case .recent: "Terakhir dibuka"
        case .running: "Yang sedang jalan"
        case .alphabetical: "Abjad"
        }
    }
}

enum DockIconSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Kecil"
        case .medium: "Sedang"
        case .large: "Besar"
        }
    }
    /// Lebar satu slot dan ukuran ikon (pt). Tinggi Touch Bar 30 pt membatasi ikon terbesar.
    var slot: CGFloat { self == .small ? 28 : self == .medium ? 32 : 36 }
    var icon: CGFloat { self == .small ? 19 : self == .medium ? 23 : 26 }
}

/// Isi Dock: urutan persis lewat Accessibility (termasuk aplikasi yang sedang jalan dan badge),
/// atau tanpa izin: aplikasi yang di-pin di pengaturan Dock + aplikasi yang sedang jalan.
final class DockSource {
    private(set) var apps: [DockApp] = []
    private let queue = DispatchQueue(label: "bilah.dock")
    private var loading = false

    func refresh(_ done: @escaping () -> Void) {
        guard !loading else { return }
        loading = true
        let trusted = SystemActions.hasAccessibility
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        queue.async { [weak self] in
            var found = (trusted && dockPID != nil) ? Self.readAX(pid: dockPID!) : []
            if found.isEmpty { found = Self.readDefaults(running: running, regular: regular) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                if found != self.apps {
                    self.apps = found
                    done()
                }
            }
        }
    }

    private static func readAX(pid: pid_t) -> [DockApp] {
        func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.6)
        var out: [DockApp] = []
        for list in (attr(app, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            for item in (attr(list, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                guard attr(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                      let url = (attr(item, kAXURLAttribute) as? URL) ?? (attr(item, kAXURLAttribute) as? NSURL as URL?)
                else { continue }
                let bundleID = Bundle(url: url)?.bundleIdentifier
                guard !out.contains(where: { $0.url == url }) else { continue }
                out.append(DockApp(bundleID: bundleID, name: attr(item, kAXTitleAttribute) as? String ?? url.lastPathComponent,
                                   url: url, running: (attr(item, "AXIsApplicationRunning") as? Bool) ?? false,
                                   badge: (attr(item, "AXStatusLabel") as? String).flatMap { $0.isEmpty ? nil : $0 }))
            }
        }
        return out
    }

    private static func readDefaults(running: Set<String>, regular: [NSRunningApplication]) -> [DockApp] {
        var out: [DockApp] = []
        let persistent = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        for tile in persistent {
            guard let id = (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  !out.contains(where: { $0.bundleID == id }) else { continue }
            out.append(DockApp(bundleID: id, name: FileManager.default.displayName(atPath: url.path)
                                .replacingOccurrences(of: ".app", with: ""), url: url, running: running.contains(id), badge: nil))
        }
        for app in regular {
            guard let id = app.bundleIdentifier, let url = app.bundleURL, !out.contains(where: { $0.bundleID == id }) else { continue }
            out.append(DockApp(bundleID: id, name: app.localizedName ?? id, url: url, running: true, badge: nil))
        }
        return out
    }
}

/// Aplikasi yang terakhir dibuka (paling baru di depan), diingat antar-sesi.
final class RecentApps {
    static let shared = RecentApps()
    private(set) var order: [String]
    private var observer: NSObjectProtocol?

    private init() {
        order = UserDefaults.standard.stringArray(forKey: "dockRecent") ?? []
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            self?.touch(id)
        }
    }

    func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > 60 { order.removeLast(order.count - 60) }
        UserDefaults.standard.set(order, forKey: "dockRecent")
    }

    /// Urutkan: yang pernah dibuka (terbaru dulu), sisanya mengikuti urutan semula.
    func sorted(_ apps: [DockApp]) -> [DockApp] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return apps.enumerated().sorted { a, b in
            let ra = a.element.bundleID.flatMap { rank[$0] } ?? Int.max
            let rb = b.element.bundleID.flatMap { rank[$0] } ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}
