import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio

/// Volume output default lewat CoreAudio (API publik).
enum SystemVolume {
    private static func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Ada perangkat yang volumenya bisa diatur (HDMI dan sebagian DAC tidak bisa).
    static var isAvailable: Bool {
        guard let dev = device() else { return false }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
    }

    static func get() -> Float? {
        guard let dev = device() else { return nil }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func set(_ v: Float) {
        guard let dev = device() else { return }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(min(1, max(0, v)))
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if value > 0, isMuted() { setMuted(false) }
    }

    static func isMuted() -> Bool {
        guard let dev = device() else { return false }
        var addr = address(kAudioDevicePropertyMute)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let dev = device() else { return }
        var addr = address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

/// Brightness layar bawaan. Di Apple Silicon jalur IOKit lama tidak jalan, jadi pakai DisplayServices (privat).
enum DisplayBrightness {
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let handle, let s = dlsym(handle, name) else { return nil }
        return unsafeBitCast(s, to: type)
    }

    /// Layar bawaan MacBook; kalau tutupnya ditutup (clamshell), pakai layar utama.
    private static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var isAvailable: Bool { symbol("DisplayServicesCanChangeBrightness", CanFn.self)?(display) ?? false }

    static func get() -> Float? {
        guard let fn = symbol("DisplayServicesGetBrightness", GetFn.self) else { return nil }
        var value: Float = 0
        return fn(display, &value) == 0 ? value : nil
    }

    static func set(_ v: Float) {
        _ = symbol("DisplayServicesSetBrightness", SetFn.self)?(display, min(1, max(0, v)))
    }
}

enum SystemActions {
    /// Buka toolbar Screenshot (sama dengan ⌘⇧5). Izin rekam layar tetap milik Screenshot.app, bukan Bilah.
    static func openScreenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Buka Notification Center dengan "mengklik" jam di menu bar lewat Accessibility API.
    /// Dicari lewat AXIdentifier, jadi tidak bergantung bahasa sistem. Butuh izin Aksesibilitas.
    @discardableResult
    static func openNotificationCenter() -> Bool {
        guard hasAccessibility else {
            requestAccessibility()
            return false
        }
        guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return false }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        guard let bar = element(app, "AXExtrasMenuBar") else { return false }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return false }
        for item in items {
            var ident: CFTypeRef?
            AXUIElementCopyAttributeValue(item, "AXIdentifier" as CFString, &ident)
            if ident as? String == "com.apple.menuextra.clock" {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
