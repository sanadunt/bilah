import AppKit

enum SliderKind {
    case brightness, keyboard, volume

    var tint: NSColor {
        switch self {
        case .brightness: Theme.amber
        case .keyboard: Theme.text
        case .volume: Theme.teal
        }
    }

    var isAvailable: Bool {
        switch self {
        case .brightness: DisplayBrightness.isAvailable
        case .keyboard: KeyboardBacklight.isAvailable
        case .volume: SystemVolume.isAvailable
        }
    }

    func read() -> (value: CGFloat, muted: Bool)? {
        switch self {
        case .brightness: DisplayBrightness.get().map { (CGFloat($0), false) }
        case .keyboard: KeyboardBacklight.get().map { (CGFloat($0), false) }
        case .volume: SystemVolume.get().map { (CGFloat($0), SystemVolume.isMuted()) }
        }
    }

    func write(_ v: CGFloat) {
        switch self {
        case .brightness: DisplayBrightness.set(Float(v))
        case .keyboard: KeyboardBacklight.set(Float(v))
        case .volume: SystemVolume.set(Float(v))
        }
    }

    func symbol(value: CGFloat, muted: Bool) -> String {
        switch self {
        case .brightness:
            return value < 0.4 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard:
            return value < 0.05 ? "light.min" : "light.max"
        case .volume:
            if muted { return "speaker.slash.fill" }
            if value <= 0.001 { return "speaker.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }
}

// MARK: - Menggambar satu tombol pintasan (dipakai widget dan panel)

enum ShortcutButton {
    static func width(_ action: ShortcutAction, compact: Bool) -> CGFloat {
        if case .shortcut(let name) = action {
            return min(120, max(50, Draw.width(name, Theme.font(10, .semibold)) + 20))
        }
        return compact ? 31 : 40
    }

    /// `pill` = latar kapsul sendiri (panel); widget memakai kapsul bersama.
    static func draw(_ action: ShortcutAction, in r: NSRect, states: ShortcutStates, pressed: Bool, attention: Bool,
                     pill: Bool) {
        let builtin = action.builtin
        let active = builtin.map(states.isActive) ?? false
        let tint = builtin?.tint ?? Theme.text

        if pill {
            let fill = active ? tint.withAlphaComponent(0.28) : Theme.pill
            Draw.roundedRect(r, radius: Theme.radius, fill: pressed ? Theme.pillPressed : fill)
        } else if pressed {
            Draw.circle(NSPoint(x: r.midX, y: r.midY), 13, Theme.pillPressed)
        } else if active {
            Draw.circle(NSPoint(x: r.midX, y: r.midY), 12.5, tint.withAlphaComponent(0.25))
        }

        let center = NSPoint(x: r.midX, y: r.midY)
        let alpha: CGFloat = attention ? 0.4 + 0.6 * CGFloat((sin(Animator.now * 10) + 1) / 2) : 1

        switch action {
        case .app(let path):
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.draw(in: NSRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22), from: .zero,
                      operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        case .shortcut(let name):
            Draw.centered(name, Theme.font(10, .semibold), Theme.text.withAlphaComponent(alpha), x: r.minX + 6,
                          width: r.width - 12, centerY: center.y, align: .center)
        case .builtin(let b):
            let level = states.level(b)
            var symbol = b.symbol
            if let kind = b.slider, let level { symbol = kind.symbol(value: level, muted: b == .volume && states.muted) }
            let color = attention ? Theme.amber : (active ? tint : Theme.text)
            let iconCenter = level == nil ? center : NSPoint(x: center.x, y: center.y - 2.5)
            Draw.symbol(symbol, size: 12, weight: .medium, color: color, center: iconCenter, alpha: alpha)
            if let level {
                let track = NSRect(x: center.x - 8, y: center.y + 8, width: 16, height: 2)
                Draw.roundedRect(track, radius: 1, fill: Theme.track)
                var fill = track
                fill.size.width = track.width * min(1, max(0, level))
                let muted = b == .volume && states.muted
                Draw.roundedRect(fill, radius: 1, fill: muted ? Theme.secondary : (b.slider?.tint ?? tint))
            }
        }
    }
}

// MARK: - Widget pintasan cepat (tombol yang di-pin + ⋯)

final class ControlsWidget: Widget {
    let kind = WidgetKind.controls
    var onOpenPanel: (() -> Void)?

    private let settings: SettingsStore
    private let runner: ShortcutRunner
    private let views = ViewSet<ControlsView>()

    init(settings: SettingsStore, runner: ShortcutRunner) {
        self.settings = settings
        self.runner = runner
    }

    func makeView() -> WidgetView {
        let v = ControlsView(actions: settings.pinnedActions)
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            switch v.item(at: p) {
            case .more: self.onOpenPanel?()
            case .action(let a):
                if !self.runner.run(a) { v.flash(a) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
            case nil: break
            }
        }
        views.add(v)
        refresh()
        return v
    }

    func tick() { refresh() }

    private func refresh() {
        let states = ShortcutStates.current(for: settings.pinnedActions)
        views.forEach {
            $0.states = states
            $0.needsDisplay = true
        }
    }
}

final class ControlsView: WidgetView {
    enum Item: Equatable { case action(ShortcutAction), more }

    private static let pad: CGFloat = 3
    private let items: [(item: Item, x: CGFloat, width: CGFloat)]
    var states = ShortcutStates()
    private var attention: (id: String, until: Date)?

    override var highlightsWhole: Bool { false }

    init(actions: [ShortcutAction]) {
        var x = Self.pad
        var list: [(Item, CGFloat, CGFloat)] = []
        for a in actions {
            let w = ShortcutButton.width(a, compact: true)
            list.append((.action(a), x, w))
            x += w
        }
        list.append((.more, x, 31))
        items = list.map { (item: $0.0, x: $0.1, width: $0.2) }
        super.init(width: x + 31 + Self.pad)
    }

    required init?(coder: NSCoder) { fatalError() }

    func item(at p: NSPoint) -> Item? {
        items.first { p.x >= $0.x && p.x < $0.x + $0.width }?.item
    }

    func flash(_ action: ShortcutAction) {
        attention = (action.id, Date() + 2.5)
        animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.animating = false }
    }

    override func drawContent(_ b: NSRect) {
        let pressed = pressPoint.flatMap(item(at:))
        for entry in items {
            let r = NSRect(x: entry.x, y: 0, width: entry.width, height: b.height)
            switch entry.item {
            case .more:
                if pressed == .more { Draw.circle(NSPoint(x: r.midX, y: r.midY), 13, Theme.pillPressed) }
                Draw.symbol("square.grid.2x2.fill", size: 11.5, weight: .medium, color: Theme.secondary,
                            center: NSPoint(x: r.midX, y: r.midY))
            case .action(let a):
                let flashing = attention.map { $0.id == a.id && $0.until > Date() } ?? false
                ShortcutButton.draw(a, in: r, states: states, pressed: pressed == entry.item, attention: flashing, pill: false)
            }
        }
    }
}

// MARK: - Panel semua pintasan (selebar Touch Bar, bisa digeser)

final class ShortcutPanelView: WidgetView {
    private static let gap: CGFloat = 5
    private let actions: [ShortcutAction]
    private let frames: [NSRect]
    private let contentWidth: CGFloat
    private var offset: CGFloat = 0
    private var touchStart: (x: CGFloat, offset: CGFloat)?
    private var scrolled = false
    private var attention: (id: String, until: Date)?

    var states = ShortcutStates()
    var onRun: ((ShortcutAction) -> Bool)?
    var onInteract: (() -> Void)?

    override var highlightsWhole: Bool { false }

    init(actions: [ShortcutAction], width: CGFloat) {
        self.actions = actions
        var x: CGFloat = 0
        var frames: [NSRect] = []
        var lastGroup: String?
        for a in actions {
            // Jarak ekstra antar-grup, seperti pengelompokan di Control Strip.
            if let lastGroup, lastGroup != a.subtitle { x += 8 }
            lastGroup = a.subtitle
            let w = ShortcutButton.width(a, compact: false)
            frames.append(NSRect(x: x, y: 0, width: w, height: Theme.height))
            x += w + Self.gap
        }
        self.frames = frames
        contentWidth = max(0, x - Self.gap)
        super.init(width: width)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var maxOffset: CGFloat { max(0, contentWidth - bounds.width) }

    private func index(at p: NSPoint) -> Int? {
        frames.firstIndex { $0.offsetBy(dx: -offset, dy: 0).contains(NSPoint(x: p.x, y: min(p.y, Theme.height - 1))) }
    }

    func flash(_ action: ShortcutAction) {
        attention = (action.id, Date() + 2.5)
        animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.animating = false }
    }

    // Sentuh: geser kalau bergerak > 6 pt, selain itu ketuk.
    override func touchesBegan(with event: NSEvent) {
        guard let t = event.touches(matching: .began, in: self).first else { return }
        begin(t.location(in: self))
    }

    override func touchesMoved(with event: NSEvent) {
        guard let t = event.touches(matching: .moved, in: self).first else { return }
        move(t.location(in: self))
    }

    override func touchesEnded(with event: NSEvent) { end(cancelled: false) }
    override func touchesCancelled(with event: NSEvent) { end(cancelled: true) }
    override func mouseDown(with event: NSEvent) { begin(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { move(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { end(cancelled: false) }

    private var pressedIndex: Int?

    private func begin(_ p: NSPoint) {
        onInteract?()
        touchStart = (p.x, offset)
        scrolled = false
        pressedIndex = index(at: p)
        needsDisplay = true
    }

    private func move(_ p: NSPoint) {
        guard let start = touchStart else { return }
        let dx = p.x - start.x
        if abs(dx) > 6 { scrolled = true; pressedIndex = nil }
        if scrolled {
            offset = min(maxOffset, max(0, start.offset - dx))
            onInteract?()
        }
        needsDisplay = true
    }

    private func end(cancelled: Bool) {
        defer {
            touchStart = nil
            pressedIndex = nil
            needsDisplay = true
        }
        guard !cancelled, !scrolled, let i = pressedIndex else { return }
        let action = actions[i]
        if onRun?(action) == false { flash(action) }
        onInteract?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Tanpa kapsul bersama: tiap tombol punya kapsul sendiri.
        drawContent(bounds)
    }

    override func drawContent(_ b: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: b).addClip()
        for (i, a) in actions.enumerated() {
            let r = frames[i].offsetBy(dx: -offset, dy: 0)
            guard r.maxX >= 0, r.minX <= b.width else { continue }
            let flashing = attention.map { $0.id == a.id && $0.until > Date() } ?? false
            ShortcutButton.draw(a, in: r, states: states, pressed: pressedIndex == i, attention: flashing, pill: true)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Bayangan di tepi menandakan masih ada tombol di luar layar.
        if offset < maxOffset { edgeFade(NSRect(x: b.maxX - 24, y: 0, width: 24, height: b.height), angle: 0) }
        if offset > 0 { edgeFade(NSRect(x: 0, y: 0, width: 24, height: b.height), angle: 180) }
    }

    private func edgeFade(_ r: NSRect, angle: CGFloat) {
        NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?.draw(in: r, angle: angle)
    }
}

// MARK: - Slider besar

/// Slider yang menggantikan dashboard sementara. Geser di mana saja di jalurnya; ketuk ikon untuk bisu (volume).
final class SliderView: WidgetView {
    let kind: SliderKind
    var value: CGFloat = 0 { didSet { needsDisplay = true } }
    var muted = false { didSet { needsDisplay = true } }
    private(set) var isTracking = false
    private var iconPressed = false

    var onChange: ((CGFloat) -> Void)?
    var onIconTap: (() -> Void)?
    /// Dipanggil tiap sentuhan, supaya timer tutup-otomatis direset.
    var onInteract: (() -> Void)?

    override var highlightsWhole: Bool { false }

    init(kind: SliderKind, width: CGFloat) {
        self.kind = kind
        super.init(width: width)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var iconZone: CGFloat { 46 }
    private var track: NSRect { NSRect(x: 56, y: bounds.midY - 3, width: bounds.width - 56 - 64, height: 6) }

    override func touchesBegan(with event: NSEvent) {
        guard let t = event.touches(matching: .began, in: self).first else { return }
        begin(t.location(in: self))
    }

    override func touchesMoved(with event: NSEvent) {
        guard let t = event.touches(matching: .moved, in: self).first else { return }
        move(t.location(in: self))
    }

    override func touchesEnded(with event: NSEvent) { end(cancelled: false) }
    override func touchesCancelled(with event: NSEvent) { end(cancelled: true) }
    override func mouseDown(with event: NSEvent) { begin(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { move(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { end(cancelled: false) }

    private func begin(_ p: NSPoint) {
        onInteract?()
        if p.x < iconZone {
            iconPressed = true
            needsDisplay = true
        } else {
            isTracking = true
            update(p)
        }
    }

    private func move(_ p: NSPoint) {
        guard isTracking else { return }
        onInteract?()
        update(p)
    }

    private func end(cancelled: Bool) {
        if iconPressed {
            iconPressed = false
            if !cancelled { onIconTap?() }
        }
        isTracking = false
        needsDisplay = true
        onInteract?()
    }

    private func update(_ p: NSPoint) {
        let v = min(1, max(0, (p.x - track.minX) / track.width))
        value = v
        if kind == .volume, v > 0 { muted = false }
        onChange?(v)
    }

    override func drawContent(_ b: NSRect) {
        let iconCenter = NSPoint(x: 26, y: b.midY)
        if iconPressed { Draw.circle(iconCenter, 13, Theme.pillPressed) }
        Draw.symbol(kind.symbol(value: value, muted: muted), size: 14, weight: .semibold,
                    color: muted ? Theme.secondary : kind.tint, center: iconCenter)

        let t = track
        Draw.roundedRect(t, radius: 3, fill: Theme.track)
        var fill = t
        fill.size.width = t.width * value
        Draw.roundedRect(fill, radius: 3, fill: muted ? Theme.secondary : kind.tint)

        let knob = NSPoint(x: t.minX + t.width * value, y: b.midY)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 3
        shadow.set()
        Draw.circle(knob, isTracking ? 10.5 : 9, Theme.text)
        NSGraphicsContext.restoreGraphicsState()

        let label = muted ? "Bisu" : "\(Int((value * 100).rounded()))%"
        Draw.centered(label, Theme.mono(12.5, .semibold), Theme.text, x: b.width - 58, width: 48, centerY: b.midY,
                      align: .right)
    }
}
