import Combine
import Foundation

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    /// Halaman dashboard; masing-masing punya susunan widget sendiri. Usap Touch Bar untuk pindah halaman.
    @Published var pages: [DashboardPage] { didSet { savePages() } }
    @Published var currentPage: Int { didSet { savePages() } }
    /// Profil per aplikasi: bundle id → halaman yang otomatis dibuka saat aplikasi itu aktif.
    @Published var appPages: [String: UUID] {
        didSet { defaults.set(try? JSONEncoder().encode(appPages), forKey: "appPages") }
    }
    @Published var autoPageSwitch: Bool { didSet { defaults.set(autoPageSwitch, forKey: "autoPageSwitch") } }
    @Published var pillStyle: PillStyle {
        didSet { defaults.set(pillStyle.rawValue, forKey: "pillStyle"); Theme.pillStyle = pillStyle }
    }
    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: "accent"); Theme.accentChoice = accent }
    }
    @Published var hideControlStrip: Bool { didSet { defaults.set(hideControlStrip, forKey: "hideControlStrip") } }
    @Published var reassertOnAppSwitch: Bool { didSet { defaults.set(reassertOnAppSwitch, forKey: "reassertOnAppSwitch") } }
    @Published var showOnPomodoroEnd: Bool { didSet { defaults.set(showOnPomodoroEnd, forKey: "showOnPomodoroEnd") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: "breakMinutes") } }
    /// Lebar pilihan pengguna per widget (pt). Tidak ada = lebar bawaan.
    @Published var widgetWidths: [String: Double] { didSet { defaults.set(widgetWidths, forKey: "widgetWidths") } }
    /// Cara memakai sisa ruang Touch Bar: isi penuh (bawaan), sebar merata, atau rapat.
    @Published var spacing: SpacingMode { didSet { defaults.set(spacing.rawValue, forKey: "spacing") } }
    /// Widget Musik: ikuti apa pun yang diputar (auto) atau satu aplikasi saja (app).
    @Published var musicMode: MusicMode { didSet { defaults.set(musicMode.rawValue, forKey: "musicMode") } }
    /// Aplikasi musik pilihan: disaring di mode satu aplikasi, dan dibuka saat belum ada yang diputar.
    @Published var musicApp: String { didSet { defaults.set(musicApp, forKey: "musicApp") } }
    /// Aplikasi tambahan yang dipilih lewat "Pilih aplikasi lain…".
    @Published var musicExtraApps: [String] { didSet { defaults.set(musicExtraApps, forKey: "musicExtraApps") } }
    /// Peliharaan di widget Peliharaan (maks 3).
    @Published var pets: [PetConfig] { didSet { defaults.set(try? JSONEncoder().encode(pets), forKey: "pets") } }
    /// Peliharaan joget saat ada musik diputar.
    @Published var petDance: Bool { didSet { defaults.set(petDance, forKey: "petDance") } }
    /// Peliharaan lebih sering tidur pukul 23.00–06.00.
    @Published var petNightSleep: Bool { didSet { defaults.set(petNightSleep, forKey: "petNightSleep") } }
    /// true = peliharaan di kotak kecil (±40 pt per ekor, tidak jalan-jalan); false = area main lebar.
    @Published var petCompact: Bool { didSet { defaults.set(petCompact, forKey: "petCompact") } }
    /// Pengingat istirahat setelah `restInterval` menit kerja tanpa jeda.
    @Published var restReminder: Bool { didSet { defaults.set(restReminder, forKey: "restReminder") } }
    @Published var restInterval: Int { didSet { defaults.set(restInterval, forKey: "restInterval") } }
    /// Kota untuk jadwal sholat dan cuaca.
    @Published var location: CityLocation {
        didSet { defaults.set(try? JSONEncoder().encode(location), forKey: "location") }
    }
    @Published var shortcuts: [ShortcutEntry] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pages = Self.loadPages(defaults)
        currentPage = defaults.object(forKey: "currentPage") as? Int ?? 0
        appPages = defaults.data(forKey: "appPages").flatMap { try? JSONDecoder().decode([String: UUID].self, from: $0) } ?? [:]
        autoPageSwitch = defaults.object(forKey: "autoPageSwitch") as? Bool ?? true
        pillStyle = defaults.string(forKey: "pillStyle").flatMap(PillStyle.init(rawValue:)) ?? .gray
        accent = defaults.string(forKey: "accent").flatMap(AccentChoice.init(rawValue:)) ?? .coral
        hideControlStrip = defaults.object(forKey: "hideControlStrip") as? Bool ?? true
        reassertOnAppSwitch = defaults.object(forKey: "reassertOnAppSwitch") as? Bool ?? false
        showOnPomodoroEnd = defaults.object(forKey: "showOnPomodoroEnd") as? Bool ?? true
        focusMinutes = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        breakMinutes = defaults.object(forKey: "breakMinutes") as? Int ?? 5
        widgetWidths = defaults.dictionary(forKey: "widgetWidths") as? [String: Double] ?? [:]
        // v0.7 menyimpan "spreadWidgets"; false (rapat) dipertahankan, selain itu pakai Isi penuh.
        spacing = defaults.string(forKey: "spacing").flatMap(SpacingMode.init(rawValue:))
            ?? (defaults.object(forKey: "spreadWidgets") as? Bool == false ? .packed : .fill)
        musicMode = defaults.string(forKey: "musicMode").flatMap(MusicMode.init(rawValue:)) ?? .auto
        musicApp = defaults.string(forKey: "musicApp") ?? MusicApps.defaultApp
        musicExtraApps = defaults.stringArray(forKey: "musicExtraApps") ?? []
        pets = defaults.data(forKey: "pets").flatMap { try? JSONDecoder().decode([PetConfig].self, from: $0) }
            ?? PetConfig.defaults
        petDance = defaults.object(forKey: "petDance") as? Bool ?? true
        petNightSleep = defaults.object(forKey: "petNightSleep") as? Bool ?? true
        petCompact = defaults.object(forKey: "petCompact") as? Bool ?? false
        restReminder = defaults.object(forKey: "restReminder") as? Bool ?? true
        restInterval = defaults.object(forKey: "restInterval") as? Int ?? 50
        location = defaults.data(forKey: "location").flatMap { try? JSONDecoder().decode(CityLocation.self, from: $0) }
            ?? CityLocation.presets[0]
        shortcuts = Self.loadShortcuts(defaults)
        if !pages.indices.contains(currentPage) { currentPage = 0 }
        Theme.pillStyle = pillStyle
        Theme.accentChoice = accent
    }

    // MARK: Halaman

    private func savePages() {
        defaults.set(try? JSONEncoder().encode(pages), forKey: "pages")
        defaults.set(currentPage, forKey: "currentPage")
    }

    /// Halaman tersimpan, atau (pertama kali) susunan widget lama jadi halaman "Utama".
    /// Widget jenis baru ditambahkan ke tiap halaman dalam keadaan tersembunyi.
    private static func loadPages(_ defaults: UserDefaults) -> [DashboardPage] {
        var pages = loadSavedPages(defaults)
        // v0.13: widget info baru tinggal di halaman sendiri, supaya halaman "Utama" tidak berubah.
        if !defaults.bool(forKey: "infoPageAdded") {
            let info: [WidgetKind] = [.prayer, .calendar, .weather, .network, .badges, .clipboard]
            pages.append(DashboardPage(name: "Info", order: info + WidgetKind.allCases.filter { !info.contains($0) },
                                       disabled: Set(WidgetKind.allCases.filter { !info.contains($0) })))
            defaults.set(true, forKey: "infoPageAdded")
        }
        return pages
    }

    private static func loadSavedPages(_ defaults: UserDefaults) -> [DashboardPage] {
        if let data = defaults.data(forKey: "pages"),
           var pages = try? JSONDecoder().decode([DashboardPage].self, from: data), !pages.isEmpty {
            for i in pages.indices {
                let missing = WidgetKind.allCases.filter { !pages[i].order.contains($0) }
                pages[i].order += missing
                pages[i].disabled.formUnion(missing)
            }
            return pages
        }
        let saved = (defaults.stringArray(forKey: "order") ?? []).compactMap(WidgetKind.init(rawValue:))
        let order = saved + WidgetKind.allCases.filter { !saved.contains($0) }
        var disabled = Set((defaults.stringArray(forKey: "disabled") ?? []).compactMap(WidgetKind.init(rawValue:)))
        disabled.formUnion(WidgetKind.allCases.filter { !WidgetKind.legacyDefaults.contains($0) && !saved.contains($0) })
        return [DashboardPage(name: "Utama", order: order, disabled: disabled)]
    }

    private var page: DashboardPage {
        get { pages[pages.indices.contains(currentPage) ? currentPage : 0] }
        set { pages[pages.indices.contains(currentPage) ? currentPage : 0] = newValue }
    }

    /// Susunan widget di halaman yang sedang tampil.
    var order: [WidgetKind] {
        get { page.order }
        set { page.order = newValue }
    }

    var disabled: Set<WidgetKind> {
        get { page.disabled }
        set { page.disabled = newValue }
    }

    func showPage(_ index: Int) {
        guard pages.indices.contains(index), index != currentPage else { return }
        currentPage = index
    }

    /// Usap: +1 = halaman berikutnya, -1 = sebelumnya (memutar).
    func turnPage(_ delta: Int) {
        guard pages.count > 1 else { return }
        currentPage = (currentPage + delta + pages.count) % pages.count
    }

    func addPage(named name: String) {
        pages.append(DashboardPage(name: name, order: WidgetKind.allCases, disabled: Set(WidgetKind.allCases)))
        currentPage = pages.count - 1
    }

    func removePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        let id = pages[index].id
        pages.remove(at: index)
        appPages = appPages.filter { $0.value != id }
        currentPage = min(currentPage, pages.count - 1)
    }

    func width(for kind: WidgetKind) -> CGFloat? { widgetWidths[kind.rawValue].map { CGFloat($0) } }

    /// Simpan susunan widget yang tampil (urutan baru) tanpa mengubah posisi widget yang tersembunyi.
    func setVisibleOrder(_ visible: [WidgetKind]) {
        var next = visible.makeIterator()
        order = order.map { disabled.contains($0) ? $0 : (next.next() ?? $0) }
    }

    /// Pintasan tersimpan + tombol bawaan baru (dari versi Bilah yang lebih baru) ditambahkan di belakang.
    private static func loadShortcuts(_ defaults: UserDefaults) -> [ShortcutEntry] {
        guard let data = defaults.data(forKey: "shortcuts"),
              let saved = try? JSONDecoder().decode([ShortcutEntry].self, from: data) else { return ShortcutEntry.defaults }
        let known = Set(saved.map(\.id))
        return saved + ShortcutEntry.defaults.filter { !known.contains($0.id) }.map {
            var e = $0
            e.pinned = false
            return e
        }
    }

    /// Tombol di widget Pintasan cepat.
    var pinnedActions: [ShortcutAction] {
        shortcuts.filter { $0.enabled && $0.pinned && $0.action.isAvailable }.prefix(ShortcutEntry.maxPinned).map(\.action)
    }

    /// Tombol di panel ⋯.
    var panelActions: [ShortcutAction] {
        shortcuts.filter { $0.enabled && $0.action.isAvailable }.map(\.action)
    }

    func addShortcut(_ action: ShortcutAction) {
        guard !shortcuts.contains(where: { $0.id == action.id }) else { return }
        shortcuts.append(ShortcutEntry(action: action, enabled: true, pinned: false))
    }

    var visibleWidgets: [WidgetKind] { order.filter { !disabled.contains($0) } }

    /// Berubah hanya kalau isi/urutan bar berubah, supaya bar tidak dibangun ulang untuk hal kecil.
    var layoutSignature: String {
        "p\(currentPage)/\(pages.count)|" + visibleWidgets.map(\.rawValue).joined(separator: ",") + "|\(hideControlStrip)|"
            + pinnedActions.map(\.id).joined(separator: ",")
            + "|" + widgetWidths.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value))" }.joined(separator: ",")
            + "|\(spacing.rawValue)|pet=\(petCompact ? "kotak" : "lebar")x\(pets.count)"
            + "|tema=\(pillStyle.rawValue)-\(accent.rawValue)"
    }

    func isEnabled(_ kind: WidgetKind) -> Bool { !disabled.contains(kind) }

    func setEnabled(_ kind: WidgetKind, _ on: Bool) {
        if on { disabled.remove(kind) } else { disabled.insert(kind) }
    }

    func move(_ kind: WidgetKind, by delta: Int) {
        guard let i = order.firstIndex(of: kind) else { return }
        let j = i + delta
        guard order.indices.contains(j) else { return }
        order.swapAt(i, j)
    }
}

enum MusicMode: String {
    case auto, app
}

struct DashboardPage: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var order: [WidgetKind]
    var disabled: Set<WidgetKind>
}
