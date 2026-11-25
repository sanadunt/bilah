import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SettingsStore()
    private let updater = Updater()
    private lazy var dashboard = DashboardController(settings: settings)
    private lazy var mainWindow = MainWindowController(store: settings, dashboard: dashboard, updater: updater)
    private var statusItem: NSStatusItem?
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleDashboard), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(openUpdates), keyEquivalent: "")
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        setupStatusItem()
        dashboard.start()
        updater.start()
        // Dibuka manual = tampilkan jendela. Dibuka otomatis saat login = langsung kerja di Touch Bar saja.
        if !launchedAtLogin { mainWindow.show() }
    }

    /// Klik ikon Bilah lagi (Finder/Launchpad/Dock) saat sudah jalan = buka jendela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        dashboard.stop()
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("Tentang Bilah", #selector(openAbout)))
        appMenu.addItem(item("Cek Update…", #selector(openUpdates)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Pengaturan…", #selector(openWindow), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Sembunyikan Bilah", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Keluar Bilah", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Salin", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Pilih Semua", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Jendela")
        windowMenu.addItem(NSMenuItem(title: "Kecilkan", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Tutup", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func setupStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Bilah")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Buka Bilah…", #selector(openWindow), key: ","))
        toggleItem.target = self
        menu.addItem(toggleItem)
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(item("Main Kejar Camilan di Touch Bar", #selector(playGame)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Keluar Bilah", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
        statusItem = status
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = dashboard.isShown ? "Sembunyikan dashboard" : "Tampilkan dashboard"
        toggleItem.isEnabled = dashboard.available
        if updater.updateAvailable, let v = updater.latest?.version {
            updateItem.title = "Update v\(v) tersedia…"
        } else {
            updateItem.title = "Cek update…"
        }
    }

    @objc private func toggleDashboard() { dashboard.toggle() }
    @objc private func playGame() { dashboard.openGame() }
    @objc private func openWindow() { mainWindow.show() }
    @objc private func openAbout() { mainWindow.show(page: .about) }

    @objc private func openUpdates() {
        mainWindow.show(page: .updates)
        if !updater.updateAvailable { updater.check() }
    }
}
