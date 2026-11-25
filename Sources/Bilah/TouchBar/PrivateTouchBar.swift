import AppKit

/// Jembatan ke API Touch Bar privat (DFRFoundation + method kelas NSTouchBar yang tidak didokumentasikan).
/// Ini cara yang sama dipakai Pock dan MTMR supaya bar tampil di semua aplikasi.
/// Semua fungsi aman dipanggil walau simbolnya hilang di versi macOS mendatang: cukup tidak melakukan apa-apa.
enum PrivateTouchBar {
    private static let dfr: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    private static func dfrSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let dfr else { return nil }
        return dlsym(dfr, name)
    }

    private static func classMethod(_ cls: AnyClass, _ name: String) -> (imp: IMP, sel: Selector)? {
        let sel = NSSelectorFromString(name)
        guard let meta = object_getClass(cls), class_respondsToSelector(meta, sel),
              let imp = class_getMethodImplementation(meta, sel) else { return nil }
        return (imp, sel)
    }

    static var isAvailable: Bool {
        dfrSymbol("DFRElementSetControlStripPresenceForIdentifier") != nil
            && classMethod(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:") != nil
            && classMethod(NSTouchBar.self, "minimizeSystemModalTouchBar:") != nil
            && classMethod(NSTouchBarItem.self, "addSystemTrayItem:") != nil
    }

    static func setControlStripPresence(_ id: NSTouchBarItem.Identifier, _ visible: Bool) {
        typealias Fn = @convention(c) (CFString, Bool) -> Void
        guard let sym = dfrSymbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(sym, to: Fn.self)(id.rawValue as CFString, visible)
    }

    static func setCloseBoxVisible(_ visible: Bool) {
        typealias Fn = @convention(c) (Bool) -> Void
        guard let sym = dfrSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        unsafeBitCast(sym, to: Fn.self)(visible)
    }

    /// placement 0 = Control Strip tetap tampil di kanan, 1 = bar memakai seluruh lebar.
    static func present(_ bar: NSTouchBar, placement: Int64, trayID: NSTouchBarItem.Identifier) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString) -> Void
        guard let m = classMethod(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:") else { return }
        unsafeBitCast(m.imp, to: Fn.self)(NSTouchBar.self as AnyObject, m.sel, bar, placement, trayID.rawValue as NSString)
    }

    static func minimize(_ bar: NSTouchBar) { call(NSTouchBar.self, "minimizeSystemModalTouchBar:", bar) }
    static func dismiss(_ bar: NSTouchBar) { call(NSTouchBar.self, "dismissSystemModalTouchBar:", bar) }
    static func addTrayItem(_ item: NSTouchBarItem) { call(NSTouchBarItem.self, "addSystemTrayItem:", item) }
    static func removeTrayItem(_ item: NSTouchBarItem) { call(NSTouchBarItem.self, "removeSystemTrayItem:", item) }

    private static func call(_ cls: AnyClass, _ name: String, _ arg: AnyObject) {
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        guard let m = classMethod(cls, name) else { return }
        unsafeBitCast(m.imp, to: Fn.self)(cls as AnyObject, m.sel, arg)
    }
}
