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
    }

    var visibleWidgets: [WidgetKind] { order.filter { !disabled.contains($0) } }

    /// Berubah hanya kalau isi/urutan bar berubah, supaya bar tidak dibangun ulang untuk hal kecil.
    var layoutSignature: String {
        visibleWidgets.map(\.rawValue).joined(separator: ",") + "|\(hideControlStrip)"
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
