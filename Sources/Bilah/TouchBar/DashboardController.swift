import AppKit
import Combine

/// Mengelola bar dashboard (system-modal, tampil di semua aplikasi) dan ikon di Control Strip.
final class DashboardController: NSObject, NSTouchBarDelegate, ObservableObject {
    static let trayID = NSTouchBarItem.Identifier("local.bilah.tray")
    static let dashboardID = NSTouchBarItem.Identifier("local.bilah.dashboard")
    static let overlayID = NSTouchBarItem.Identifier("local.bilah.overlay")

    let settings: SettingsStore
    let available = PrivateTouchBar.isAvailable
    @Published private(set) var isShown = false
    /// Jendela Bilah terbuka: widget tetap di-tick walau dashboard disembunyikan, supaya preview hidup.
    var previewActive = false

    private let claude = ClaudeWidget()
    private let pomodoro: PomodoroWidget
    private let runner = ShortcutRunner()
    private let controls: ControlsWidget
    private let widgets: [WidgetKind: Widget]

    /// Bar sementara yang menggantikan dashboard: slider (layar/keyboard/volume) atau panel semua pintasan.
    private enum Overlay {
        case slider(SliderKind)
        case panel
    }

    private var overlay: Overlay?
    private var overlayBar: NSTouchBar?
    private weak var sliderView: SliderView?
    private weak var panelView: ShortcutPanelView?
    private var overlayIdleTimer: Timer?

    // Wadah bar yang sedang tampil, supaya lebarnya bisa disesuaikan setelah Touch Bar diukur.
    private weak var dashboardContainer: BarContainerView?
    private weak var overlayContainer: BarContainerView?

    private var touchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private let trayView = TrayView()
    private var timer: Timer?
    private var settingsSub: AnyCancellable?
    private var layoutSignature = ""

    init(settings: SettingsStore) {
        self.settings = settings
        pomodoro = PomodoroWidget(settings: settings)
        controls = ControlsWidget(settings: settings, runner: runner)
        widgets = [
            .claude: claude,
            .nowPlaying: NowPlayingWidget(),
            .system: SystemWidget(),
            .pomodoro: pomodoro,
            .clock: ClockWidget(),
            .controls: controls,
        ]
        super.init()
        runner.onOpenSlider = { [weak self] kind in self?.openOverlay(.slider(kind)) }
        controls.onOpenPanel = { [weak self] in self?.openOverlay(.panel) }
    }

    func start() {
        guard available else { return }
        PrivateTouchBar.setCloseBoxVisible(false)

        trayView.onTap = { [weak self] _ in self?.show() }
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = trayView
        trayItem = item
        PrivateTouchBar.addTrayItem(item)
        PrivateTouchBar.setControlStripPresence(Self.trayID, true)

        pomodoro.onFinish = { [weak self] in
            guard let self, self.settings.showOnPomodoroEnd, !self.isShown else { return }
            self.show()
        }

        tick()
        rebuild()
        show()

        let t = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        settingsSub = settings.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.settingsChanged() }
    }

    func stop() {
        timer?.invalidate()
        if let bar = overlayBar { PrivateTouchBar.dismiss(bar) }
        if let tb = touchBar { PrivateTouchBar.dismiss(tb) }
        if let item = trayItem {
            PrivateTouchBar.setControlStripPresence(Self.trayID, false)
            PrivateTouchBar.removeTrayItem(item)
        }
    }

    func show() {
        guard let tb = touchBar else { return }
        PrivateTouchBar.present(tb, placement: settings.hideControlStrip ? 1 : 0, trayID: Self.trayID)
        isShown = true
        tick()
        measureRegion()
    }

    private var regionWidth: CGFloat { TouchBarRegion.width(hideControlStrip: settings.hideControlStrip) }

    /// Ukur lebar bar yang benar-benar tampil; kalau beda dengan yang diminta, simpan dan sesuaikan.
    private func measureRegion() {
        let hide = settings.hideControlStrip
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            TouchBarRegion.measure { [weak self] measured in
                guard let self, let measured, measured > 200, hide == self.settings.hideControlStrip else { return }
                if abs(measured - self.regionWidth) > 0.5 { TouchBarRegion.save(measured, hideControlStrip: hide) }
                self.dashboardContainer?.width = measured
                self.overlayContainer?.width = measured
                LayoutReport.region = measured
            }
        }
    }

    func hide() {
        guard let tb = touchBar else { return }
        PrivateTouchBar.minimize(tb)
        isShown = false
        PrivateTouchBar.setControlStripPresence(Self.trayID, true)
    }

    func toggle() { isShown ? hide() : show() }

    private func rebuild() {
        let tb = NSTouchBar()
        tb.delegate = self
        // Satu item selebar Touch Bar berisi tombol ‹ dan semua widget, jadi macOS tidak perlu membuang apa pun.
        tb.defaultItemIdentifiers = [Self.dashboardID]
        touchBar = tb
        layoutSignature = settings.layoutSignature
    }

    /// View baru untuk preview di jendela; ikut menerima data live dari widget yang sama.
    func makePreviewView(_ kind: WidgetKind) -> WidgetView {
        guard let widget = widgets[kind] else { return WidgetView(width: 60) }
        let v = widget.makeView()
        widget.tick()
        return v
    }

    func refreshNow() { tick() }

    // MARK: Overlay (slider dan panel pintasan)

    private func openOverlay(_ new: Overlay) {
        guard available else { return }
        if case .slider(let kind) = new, !kind.isAvailable { return }
        if let old = overlayBar { PrivateTouchBar.dismiss(old) }
        overlay = new
        let tb = NSTouchBar()
        tb.delegate = self
        tb.defaultItemIdentifiers = [Self.overlayID]
        overlayBar = tb
        PrivateTouchBar.present(tb, placement: settings.hideControlStrip ? 1 : 0, trayID: Self.trayID)
        bumpOverlayIdle()
        measureRegion()
    }

    /// Slider menutup sendiri setelah 3,5 detik tanpa sentuhan (seperti bawaan macOS), panel setelah 10 detik.
    private func bumpOverlayIdle() {
        overlayIdleTimer?.invalidate()
        let seconds: TimeInterval
        if case .panel = overlay { seconds = 10 } else { seconds = 3.5 }
        let t = Timer(timeInterval: seconds, target: self, selector: #selector(overlayIdle), userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        overlayIdleTimer = t
    }

    @objc private func overlayIdle() {
        if sliderView?.isTracking == true { bumpOverlayIdle() } else { closeOverlay() }
    }

    private func closeOverlay() {
        overlayIdleTimer?.invalidate()
        overlayIdleTimer = nil
        guard let bar = overlayBar else { return }
        overlayBar = nil
        overlay = nil
        PrivateTouchBar.dismiss(bar)
        if isShown { show() } else { PrivateTouchBar.setControlStripPresence(Self.trayID, true) }
    }

    private func makeSliderView(_ kind: SliderKind) -> SliderView {
        let v = SliderView(kind: kind, width: regionWidth)
        if let state = kind.read() {
            v.value = state.value
            v.muted = state.muted
        }
        v.onChange = { kind.write($0) }
        v.onInteract = { [weak self] in self?.bumpOverlayIdle() }
        v.onClose = { [weak self] in self?.closeOverlay() }
        v.onIconTap = { [weak v] in
            guard kind == .volume, let v else { return }
            SystemVolume.setMuted(!v.muted)
            v.muted = SystemVolume.isMuted()
        }
        sliderView = v
        return v
    }

    private func makePanelView() -> ShortcutPanelView {
        let actions = settings.panelActions
        let v = ShortcutPanelView(actions: actions, width: regionWidth - 38)
        v.states = ShortcutStates.current(for: actions)
        v.onInteract = { [weak self] in self?.bumpOverlayIdle() }
        v.onRun = { [weak self, weak v] action in
            guard let self else { return false }
            let ok = self.runner.run(action)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                v?.states = ShortcutStates.current(for: actions)
                v?.needsDisplay = true
            }
            return ok
        }
        panelView = v
        return v
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: id)
        item.visibilityPriority = .high
        switch id {
        case Self.dashboardID:
            let close = CloseView(symbol: "chevron.left")
            close.onTap = { [weak self] _ in self?.hide() }
            let strip = DashboardStripView(widgets: settings.visibleWidgets.compactMap { widgets[$0]?.makeView() })
            strip.onLayout = { available, content in LayoutReport.write(available: available, content: content) }
            let container = BarContainerView(leading: close, content: strip, width: regionWidth)
            dashboardContainer = container
            item.view = container
        case Self.overlayID:
            switch overlay {
            case .slider(let kind):
                // Slider membawa tombol + − × sendiri: [slider] [+] [−] [×].
                let container = BarContainerView(content: makeSliderView(kind), width: regionWidth)
                overlayContainer = container
                item.view = container
            case .panel:
                let close = CloseView(symbol: "xmark")
                close.onTap = { [weak self] _ in self?.closeOverlay() }
                let container = BarContainerView(content: makePanelView(), trailing: close, width: regionWidth)
                overlayContainer = container
                item.view = container
            case nil:
                return nil
            }
        default:
            return nil
        }
        return item
    }

    @objc private func tick() {
        let visible = Set(settings.visibleWidgets)
        let live = isShown || previewActive
        for (kind, widget) in widgets where widget.ticksWhenHidden || (live && visible.contains(kind)) {
            widget.tick()
        }
        trayView.state = claude.headline

        // Ikuti perubahan dari tombol keyboard saat overlay terbuka.
        if let v = sliderView, !v.isTracking, case .slider(let kind) = overlay, let state = kind.read() {
            v.value = state.value
            v.muted = state.muted
        }
        if let v = panelView, case .panel = overlay {
            v.states = ShortcutStates.current(for: settings.panelActions)
            v.needsDisplay = true
        }
    }

    @objc private func appActivated(_ note: Notification) {
        if isShown && settings.reassertOnAppSwitch { show() }
    }

    private func settingsChanged() {
        guard available, settings.layoutSignature != layoutSignature else { return }
        let wasShown = isShown
        if let old = touchBar { PrivateTouchBar.dismiss(old) }
        rebuild()
        if wasShown { show() } else { PrivateTouchBar.setControlStripPresence(Self.trayID, true) }
    }
}

/// Catatan kecil lebar strip yang benar-benar diberikan Touch Bar, untuk diagnosis
/// (~/Library/Application Support/Bilah/layout.json).
enum LayoutReport {
    /// Lebar Touch Bar terukur terakhir (dari Accessibility).
    static var region: CGFloat?

    static func write(available: CGFloat, content: CGFloat) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilah", isDirectory: true)
        let report: [String: Any] = [
            "version": Updater.currentVersion,
            "stripWidth": Double(available),
            "contentWidth": Double(content),
            "scrollable": content > available + 0.5,
            "measuredRegion": region.map { Double($0) } ?? NSNull(),
            "updated": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("layout.json"), options: .atomic)
    }
}
