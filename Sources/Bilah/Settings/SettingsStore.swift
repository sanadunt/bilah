import Combine
import Foundation

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var order: [WidgetKind] { didSet { defaults.set(order.map(\.rawValue), forKey: "order") } }
    @Published var disabled: Set<WidgetKind> { didSet { defaults.set(disabled.map(\.rawValue), forKey: "disabled") } }
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
    @Published var shortcuts: [ShortcutEntry] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.stringArray(forKey: "order") ?? []).compactMap(WidgetKind.init(rawValue:))
        order = saved + WidgetKind.allCases.filter { !saved.contains($0) }
        disabled = Set((defaults.stringArray(forKey: "disabled") ?? []).compactMap(WidgetKind.init(rawValue:)))
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
        shortcuts = Self.loadShortcuts(defaults)
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
        visibleWidgets.map(\.rawValue).joined(separator: ",") + "|\(hideControlStrip)|"
            + pinnedActions.map(\.id).joined(separator: ",")
            + "|" + widgetWidths.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value))" }.joined(separator: ",")
            + "|\(spacing.rawValue)|pet=\(petCompact ? "kotak" : "lebar")x\(pets.count)"
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
