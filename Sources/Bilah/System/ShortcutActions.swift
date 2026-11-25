import AppKit
import ApplicationServices
import Carbon
import IOKit.pwr_mgt

enum ShortcutGroup: String, CaseIterable {
    case display = "Layar"
    case media = "Suara & media"
    case windows = "Jendela"
    case system = "Sistem"
    case extra = "Ekstra"
    case custom = "Tambahan kamu"
}

/// Semua tombol bawaan Touch Bar Mac (Control Strip) plus beberapa ekstra.
enum BuiltinAction: String, CaseIterable, Codable {
    case brightness, keyboardBrightness, nightShift, darkMode
    case volume, mute, previous, playPause, next
    case missionControl, appExpose, showDesktop, apps
    case spotlight, siri, screenshot, notificationCenter, controlCenter, lockScreen, sleep, screenSaver
    case inputSource, emoji, keepAwake, game

    var title: String {
        switch self {
        case .brightness: "Kecerahan layar"
        case .keyboardBrightness: "Lampu keyboard"
        case .nightShift: "Night Shift"
        case .darkMode: "Mode gelap"
        case .volume: "Volume"
        case .mute: "Bisu"
        case .previous: "Lagu sebelumnya"
        case .playPause: "Putar / jeda"
        case .next: "Lagu berikutnya"
        case .missionControl: "Mission Control"
        case .appExpose: "Jendela aplikasi (App Exposé)"
        case .showDesktop: "Tampilkan desktop"
        case .apps: "Apps (Launchpad)"
        case .spotlight: "Spotlight"
        case .siri: "Siri"
        case .screenshot: "Screenshot"
        case .notificationCenter: "Notification Center"
        case .controlCenter: "Control Center (Focus, Wi-Fi, dll)"
        case .lockScreen: "Kunci layar"
        case .sleep: "Sleep"
        case .screenSaver: "Screen saver"
        case .inputSource: "Ganti bahasa keyboard"
        case .emoji: "Emoji & simbol"
        case .keepAwake: "Kafein (Mac tetap melek)"
        case .game: "Game: Kejar Camilan"
        }
    }

    var symbol: String {
        switch self {
        case .brightness: "sun.max.fill"
        case .keyboardBrightness: "light.max"
        case .nightShift: "sunset.fill"
        case .darkMode: "circle.lefthalf.filled"
        case .volume: "speaker.wave.2.fill"
        case .mute: "speaker.slash.fill"
        case .previous: "backward.fill"
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "macwindow.on.rectangle"
        case .showDesktop: "menubar.dock.rectangle"
        case .apps: "square.grid.3x3.fill"
        case .spotlight: "magnifyingglass"
        case .siri: "waveform.circle.fill"
        case .screenshot: "camera.viewfinder"
        case .notificationCenter: "bell.fill"
        case .controlCenter: "switch.2"
        case .lockScreen: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .screenSaver: "sparkles.tv"
        case .inputSource: "globe"
        case .emoji: "face.smiling"
        case .keepAwake: "cup.and.saucer.fill"
        case .game: "gamecontroller.fill"
        }
    }

    var group: ShortcutGroup {
        switch self {
        case .brightness, .keyboardBrightness, .nightShift, .darkMode: .display
        case .volume, .mute, .previous, .playPause, .next: .media
        case .missionControl, .appExpose, .showDesktop, .apps: .windows
        case .spotlight, .siri, .screenshot, .notificationCenter, .controlCenter, .lockScreen, .sleep, .screenSaver,
             .inputSource: .system
        case .emoji, .keepAwake, .game: .extra
        }
    }

    /// Aksi yang membuka slider, bukan langsung dijalankan.
    var slider: SliderKind? {
        switch self {
        case .brightness: .brightness
        case .keyboardBrightness: .keyboard
        case .volume: .volume
        default: nil
        }
    }

    var isToggle: Bool { [.nightShift, .darkMode, .mute, .keepAwake].contains(self) }

    /// Butuh izin Aksesibilitas (mengirim tombol keyboard/media atau mengklik menu bar).
    var needsAccessibility: Bool {
        [.previous, .playPause, .next, .spotlight, .emoji, .notificationCenter, .controlCenter].contains(self)
    }

    var tint: NSColor {
        switch self {
        case .brightness, .nightShift: Theme.amber
        case .volume: Theme.teal
        case .mute: Theme.red
        case .darkMode: Theme.violet
        case .keepAwake: Theme.coral
        case .game: Theme.violet
        default: Theme.text
        }
    }

    var isAvailable: Bool {
        switch self {
        case .keyboardBrightness: KeyboardBacklight.isAvailable
        case .nightShift: NightShift.isAvailable
        case .inputSource: InputSources.list().count > 1
        default: true
        }
    }

    var unavailableReason: String {
        switch self {
        case .inputSource: "Cuma ada satu bahasa keyboard di Mac ini."
        default: "Tidak tersedia di Mac ini."
        }
    }
}

enum ShortcutAction: Codable, Hashable {
    case builtin(BuiltinAction)
    case app(path: String)
    case shortcut(name: String)

    var id: String {
        switch self {
        case .builtin(let b): "builtin:\(b.rawValue)"
        case .app(let path): "app:\(path)"
        case .shortcut(let name): "shortcut:\(name)"
        }
    }

    var title: String {
        switch self {
        case .builtin(let b): b.title
        case .app(let path): FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        case .shortcut(let name): name
        }
    }

    var subtitle: String {
        switch self {
        case .builtin(let b): b.group.rawValue
        case .app: "Aplikasi"
        case .shortcut: "Shortcut"
        }
    }

    var builtin: BuiltinAction? {
        if case .builtin(let b) = self { return b }
        return nil
    }

    var isAvailable: Bool {
        switch self {
        case .builtin(let b): b.isAvailable
        case .app(let path): FileManager.default.fileExists(atPath: path)
        case .shortcut: true
        }
    }
}

struct ShortcutEntry: Codable, Hashable, Identifiable {
    var action: ShortcutAction
    var enabled: Bool
    var pinned: Bool

    var id: String { action.id }

    static let maxPinned = 6

    static var defaults: [ShortcutEntry] {
        BuiltinAction.allCases.map {
            ShortcutEntry(action: .builtin($0), enabled: $0 != .inputSource,
                          pinned: [.brightness, .volume, .screenshot, .notificationCenter].contains($0))
        }
    }
}

// MARK: - Status untuk digambar (level slider dan toggle)

struct ShortcutStates {
    var brightness: CGFloat?
    var keyboard: CGFloat?
    var volume: CGFloat?
    var muted = false
    var nightShift = false
    var darkMode = false
    var keepAwake = false

    /// Hanya membaca yang memang tampil, supaya tick tiap detik tetap ringan.
    static func current(for actions: [ShortcutAction]) -> ShortcutStates {
        let b = Set(actions.compactMap(\.builtin))
        var s = ShortcutStates()
        if b.contains(.brightness) { s.brightness = DisplayBrightness.get().map { CGFloat($0) } }
        if b.contains(.keyboardBrightness) { s.keyboard = KeyboardBacklight.get().map { CGFloat($0) } }
        if b.contains(.volume) || b.contains(.mute) {
            s.volume = SystemVolume.get().map { CGFloat($0) }
            s.muted = SystemVolume.isMuted()
        }
        if b.contains(.nightShift) { s.nightShift = NightShift.isOn }
        if b.contains(.darkMode) { s.darkMode = DarkMode.isOn }
        s.keepAwake = KeepAwake.isOn
        return s
    }

    func level(_ b: BuiltinAction) -> CGFloat? {
        switch b {
        case .brightness: brightness
        case .keyboardBrightness: keyboard
        case .volume: volume
        default: nil
        }
    }

    func isActive(_ b: BuiltinAction) -> Bool {
        switch b {
        case .nightShift: nightShift
        case .darkMode: darkMode
        case .mute: muted
        case .keepAwake: keepAwake
        default: false
        }
    }
}

// MARK: - Menjalankan aksi

final class ShortcutRunner {
    var onOpenSlider: ((SliderKind) -> Void)?
    var onOpenGame: (() -> Void)?

    /// false = gagal, biasanya karena izin Aksesibilitas belum ada (dialognya sudah diminta).
    @discardableResult
    func run(_ action: ShortcutAction) -> Bool {
        switch action {
        case .app(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            return true
        case .shortcut(let name):
            SystemShortcuts.runShortcut(name)
            return true
        case .builtin(let b):
            if b.needsAccessibility && !SystemActions.hasAccessibility {
                SystemActions.requestAccessibility()
                return false
            }
            return run(b)
        }
    }

    private func run(_ b: BuiltinAction) -> Bool {
        if let kind = b.slider {
            guard kind.isAvailable else { return false }
            onOpenSlider?(kind)
            return true
        }
        switch b {
        case .nightShift: NightShift.set(!NightShift.isOn)
        case .darkMode: DarkMode.set(!DarkMode.isOn)
        case .mute: SystemVolume.setMuted(!SystemVolume.isMuted())
        case .keepAwake: KeepAwake.toggle()
        case .previous: SystemShortcuts.mediaKey(SystemShortcuts.keyPrevious)
        case .playPause: SystemShortcuts.mediaKey(SystemShortcuts.keyPlay)
        case .next: SystemShortcuts.mediaKey(SystemShortcuts.keyNext)
        case .missionControl: SystemShortcuts.dock("com.apple.expose.awake")
        case .appExpose: SystemShortcuts.dock("com.apple.expose.front.awake")
        case .showDesktop: SystemShortcuts.dock("com.apple.showdesktop.awake")
        case .apps: SystemShortcuts.openApps()
        case .spotlight: SystemShortcuts.keyCombo(49, .maskCommand)
        case .emoji: SystemShortcuts.keyCombo(49, [.maskCommand, .maskControl])
        case .siri: SystemShortcuts.openApp("/System/Applications/Siri.app")
        case .screenshot: SystemActions.openScreenshot()
        case .notificationCenter: return SystemActions.openNotificationCenter()
        case .controlCenter: return SystemActions.openControlCenter()
        case .lockScreen: SystemShortcuts.lockScreen()
        case .sleep: SystemShortcuts.sleepNow()
        case .screenSaver: SystemShortcuts.openApp("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .inputSource: InputSources.selectNext()
        case .game: onOpenGame?()
        case .brightness, .keyboardBrightness, .volume: break
        }
        return true
    }
}

enum SystemShortcuts {
    static let keyPlay: Int32 = 16, keyNext: Int32 = 17, keyPrevious: Int32 = 18

    private static let appServices = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
    private static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)

    /// Notifikasi Dock privat: Mission Control, App Exposé, Show Desktop.
    static func dock(_ name: String) {
        typealias Fn = @convention(c) (CFString, Int32) -> Void
        guard let appServices, let s = dlsym(appServices, "CoreDockSendNotification") else { return }
        unsafeBitCast(s, to: Fn.self)(name as CFString, 0)
    }

    /// Tombol media sistem (sama dengan F7–F9), diteruskan macOS ke pemutar mana pun yang aktif.
    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func keyCombo(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    /// macOS 26 mengganti Launchpad dengan Apps.app; versi lama pakai notifikasi Dock.
    static func openApps() {
        let apps = "/System/Applications/Apps.app"
        if FileManager.default.fileExists(atPath: apps) { openApp(apps) } else { dock("com.apple.launchpad.toggle") }
    }

    static func lockScreen() {
        typealias Fn = @convention(c) () -> Int32
        if let login, let s = dlsym(login, "SACLockScreenImmediate") {
            _ = unsafeBitCast(s, to: Fn.self)()
        } else {
            keyCombo(12, [.maskCommand, .maskControl]) // ⌃⌘Q
        }
    }

    static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }

    static func runShortcut(_ name: String) { run("/usr/bin/shortcuts", ["run", name]) }

    /// Daftar Shortcuts milik pengguna (dari app Shortcuts).
    static func listShortcuts() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// Night Shift lewat CoreBrightness (privat).
enum NightShift {
    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    static var isAvailable: Bool { client != nil }

    static var isOn: Bool {
        guard let client else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel) else { return false }
        var status = [UInt8](repeating: 0, count: 64)
        let ok = status.withUnsafeMutableBytes { unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, $0.baseAddress!) }
        return ok && status[1] != 0 // byte 1 = "enabled" (sedang menyala)
    }

    static func set(_ on: Bool) {
        guard let client else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { return }
        _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, on)
    }
}

/// Lampu keyboard lewat CoreBrightness (privat).
enum KeyboardBacklight {
    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    private static var keyboardID: UInt64? {
        guard let client, client.responds(to: NSSelectorFromString("copyKeyboardBacklightIDs")),
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        let sel = NSSelectorFromString("isKeyboardBuiltIn:")
        if client.responds(to: sel) {
            let builtIn = ids.first { unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, $0.uint64Value) }
            if let builtIn { return builtIn.uint64Value }
        }
        return ids.first?.uint64Value
    }

    static var isAvailable: Bool { keyboardID != nil }

    static func get() -> Float? {
        guard let client, let id = keyboardID else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, id)
    }

    static func set(_ v: Float) {
        guard let client, let id = keyboardID else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        _ = unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, min(1, max(0, v)), id)
    }
}

/// Mode gelap lewat SkyLight (privat), tanpa perlu izin Automation ke System Events.
enum DarkMode {
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    static var isOn: Bool {
        typealias Fn = @convention(c) () -> Bool
        guard let sky, let s = dlsym(sky, "SLSGetAppearanceThemeLegacy") else { return false }
        return unsafeBitCast(s, to: Fn.self)()
    }

    static func set(_ on: Bool) {
        typealias Fn = @convention(c) (Bool) -> Void
        guard let sky, let s = dlsym(sky, "SLSSetAppearanceThemeLegacy") else { return }
        unsafeBitCast(s, to: Fn.self)(on)
    }
}

/// Kafein: tahan layar dan Mac agar tidak tidur selama aktif (dilepas saat Bilah ditutup).
enum KeepAwake {
    private static var assertion: IOPMAssertionID = 0

    static var isOn: Bool { assertion != 0 }

    static func toggle() {
        if isOn {
            IOPMAssertionRelease(assertion)
            assertion = 0
        } else {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Bilah: Kafein" as CFString, &id)
            if r == kIOReturnSuccess { assertion = id }
        }
    }
}

enum InputSources {
    static func list() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsSelectCapable: true,
                      kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary
        return TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func id(_ source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static func selectNext() {
        let all = list()
        guard all.count > 1 else { return }
        let current = id(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
        let i = all.firstIndex { id($0) == current } ?? -1
        TISSelectInputSource(all[(i + 1) % all.count])
    }
}
