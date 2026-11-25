import AppKit
import Combine

/// Mengelola bar dashboard (system-modal, tampil di semua aplikasi) dan ikon di Control Strip.
final class DashboardController: NSObject, NSTouchBarDelegate, ObservableObject {
    static let trayID = NSTouchBarItem.Identifier("local.bilah.tray")
    static let closeID = NSTouchBarItem.Identifier("local.bilah.close")
    static let overlayCloseID = NSTouchBarItem.Identifier("local.bilah.overlay.close")
    static let sliderID = NSTouchBarItem.Identifier("local.bilah.slider")
    static let panelID = NSTouchBarItem.Identifier("local.bilah.panel")

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
        var ids: [NSTouchBarItem.Identifier] = [Self.closeID]
        for (i, kind) in settings.visibleWidgets.enumerated() {
            ids.append(i == 0 ? .fixedSpaceSmall : .flexibleSpace)
            ids.append(kind.identifier)
        }
        tb.defaultItemIdentifiers = ids
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
        switch new {
        case .slider: tb.defaultItemIdentifiers = [Self.overlayCloseID, .fixedSpaceSmall, Self.sliderID, .flexibleSpace]
        case .panel: tb.defaultItemIdentifiers = [Self.overlayCloseID, .fixedSpaceSmall, Self.panelID]
        }
        overlayBar = tb
        PrivateTouchBar.present(tb, placement: settings.hideControlStrip ? 1 : 0, trayID: Self.trayID)
        bumpOverlayIdle()
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

    private var overlayWidth: CGFloat { settings.hideControlStrip ? 940 : 700 }

    private func makeSliderView(_ kind: SliderKind) -> SliderView {
        let v = SliderView(kind: kind, width: overlayWidth - 40)
        if let state = kind.read() {
            v.value = state.value
            v.muted = state.muted
        }
        v.onChange = { kind.write($0) }
        v.onInteract = { [weak self] in self?.bumpOverlayIdle() }
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
        let v = ShortcutPanelView(actions: actions, width: overlayWidth)
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
        if id == Self.closeID || id == Self.overlayCloseID {
            let v = CloseView()
            v.onTap = { [weak self] _ in id == Self.closeID ? self?.hide() : self?.closeOverlay() }
            item.view = v
            return item
        }
        if id == Self.sliderID, case .slider(let kind) = overlay {
            item.view = makeSliderView(kind)
            item.visibilityPriority = .high
            return item
        }
        if id == Self.panelID {
            item.view = makePanelView()
            item.visibilityPriority = .high
            return item
        }
        guard let kind = WidgetKind.allCases.first(where: { $0.identifier == id }), let widget = widgets[kind] else {
            return nil
        }
        item.view = widget.makeView()
        item.visibilityPriority = kind.priority
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
