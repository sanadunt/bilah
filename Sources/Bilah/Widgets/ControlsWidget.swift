import AppKit

enum SliderKind {
    case brightness, volume

    var tint: NSColor { self == .brightness ? Theme.amber : Theme.teal }

    var isAvailable: Bool { self == .brightness ? DisplayBrightness.isAvailable : SystemVolume.isAvailable }

    func read() -> (value: CGFloat, muted: Bool)? {
        switch self {
        case .brightness: DisplayBrightness.get().map { (CGFloat($0), false) }
        case .volume: SystemVolume.get().map { (CGFloat($0), SystemVolume.isMuted()) }
        }
    }

    func write(_ v: CGFloat) {
        switch self {
        case .brightness: DisplayBrightness.set(Float(v))
        case .volume: SystemVolume.set(Float(v))
        }
    }

    func symbol(value: CGFloat, muted: Bool) -> String {
        switch self {
        case .brightness:
            return value < 0.4 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted { return "speaker.slash.fill" }
            if value <= 0.001 { return "speaker.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }
}

/// Empat tombol ala Control Strip: brightness, volume, screenshot, Notification Center.
/// Brightness/volume membuka slider selebar Touch Bar.
final class ControlsWidget: Widget {
    let kind = WidgetKind.controls
    var onOpenSlider: ((SliderKind) -> Void)?
    private let views = ViewSet<ControlsView>()

    func makeView() -> WidgetView {
        let v = ControlsView()
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            self.handle(v.button(at: p))
        }
        views.add(v)
        refresh()
        return v
    }

    func tick() { refresh() }

    private func refresh() {
        let brightness = DisplayBrightness.get().map { CGFloat($0) }
        let volume = SystemVolume.get().map { CGFloat($0) }
        let muted = SystemVolume.isMuted()
        views.forEach { v in
            v.brightness = brightness
            v.volume = volume
            v.muted = muted
            v.needsDisplay = true
        }
    }

    private func handle(_ button: ControlsView.Button) {
        switch button {
        case .brightness: if SliderKind.brightness.isAvailable { onOpenSlider?(.brightness) }
        case .volume: if SliderKind.volume.isAvailable { onOpenSlider?(.volume) }
        case .screenshot: SystemActions.openScreenshot()
        case .notifications:
            // Gagal = biasanya izin Aksesibilitas belum ada; macOS sudah menampilkan dialognya.
            if !SystemActions.openNotificationCenter() { views.forEach { $0.flashNotifications() } }
        }
    }
}

final class ControlsView: WidgetView {
    enum Button: Int, CaseIterable { case brightness, volume, screenshot, notifications }
    private static let buttonWidth: CGFloat = 31
    private static let pad: CGFloat = 3

    var brightness: CGFloat?
    var volume: CGFloat?
    var muted = false
    private var attentionUntil = Date.distantPast

    override var highlightsWhole: Bool { false }

    init() { super.init(width: Self.pad * 2 + Self.buttonWidth * 4) }
    required init?(coder: NSCoder) { fatalError() }

    func button(at p: NSPoint) -> Button {
        Button(rawValue: min(3, max(0, Int((p.x - Self.pad) / Self.buttonWidth))))!
    }

    func flashNotifications() {
        attentionUntil = Date() + 2.5
        animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.animating = false }
    }

    private func center(_ b: Button) -> NSPoint {
        NSPoint(x: Self.pad + Self.buttonWidth * (CGFloat(b.rawValue) + 0.5), y: bounds.midY)
    }

    override func drawContent(_ b: NSRect) {
        let pressed = pressPoint.map(button(at:))
        for button in Button.allCases {
            let c = center(button)
            if pressed == button { Draw.circle(c, 13, Theme.pillPressed) }
            switch button {
            case .brightness: drawLevel(.brightness, value: brightness, muted: false, at: c)
            case .volume: drawLevel(.volume, value: volume, muted: muted, at: c)
            case .screenshot:
                Draw.symbol("camera.viewfinder", size: 13, weight: .medium, color: Theme.text, center: c)
            case .notifications:
                let attention = attentionUntil > Date()
                let alpha = attention ? 0.4 + 0.6 * CGFloat((sin(Animator.now * 10) + 1) / 2) : 1
                Draw.symbol("bell.fill", size: 12, weight: .medium, color: attention ? Theme.amber : Theme.text,
                            center: c, alpha: alpha)
            }
        }
    }

    /// Ikon dengan garis level tipis di bawahnya.
    private func drawLevel(_ kind: SliderKind, value: CGFloat?, muted: Bool, at c: NSPoint) {
        guard let value else {
            Draw.symbol(kind.symbol(value: 1, muted: false), size: 12, weight: .medium, color: Theme.faint, center: c)
            return
        }
        Draw.symbol(kind.symbol(value: value, muted: muted), size: 12, weight: .medium, color: Theme.text,
                    center: NSPoint(x: c.x, y: c.y - 2.5))
        let track = NSRect(x: c.x - 8, y: c.y + 8, width: 16, height: 2)
        Draw.roundedRect(track, radius: 1, fill: Theme.track)
        var fill = track
        fill.size.width = track.width * min(1, max(0, value))
        Draw.roundedRect(fill, radius: 1, fill: muted ? Theme.secondary : kind.tint)
    }
}

/// Slider besar yang menggantikan dashboard sementara. Geser di mana saja di jalurnya; ketuk ikon untuk bisu (volume).
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
