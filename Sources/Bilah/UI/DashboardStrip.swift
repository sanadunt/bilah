import AppKit

/// Semua widget dashboard dalam satu item Touch Bar yang lebarnya mengikuti ruang yang tersedia,
/// jadi tidak ada widget yang disembunyikan macOS. Kalau isinya lebih lebar, strip bisa digeser.
/// Strip menerima semua sentuhan dan meneruskan ketukan ke widget di bawah jari.
final class DashboardStripView: NSView {
    static let minGap: CGFloat = 6

    private let widgets: [WidgetView]
    private let spread: Bool
    private let fade = EdgeFadeView()
    private var plan = StripLayout.Plan(frames: [], contentWidth: 0)
    private var offset: CGFloat = 0
    private var touchStart: (x: CGFloat, offset: CGFloat)?
    private var target: WidgetView?
    private var scrolling = false

    /// Dipanggil tiap tata letak berubah: (lebar tersedia, lebar isi).
    var onLayout: ((CGFloat, CGFloat) -> Void)?

    init(widgets: [WidgetView], spread: Bool = true) {
        self.widgets = widgets
        self.spread = spread
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Theme.height))
        allowedTouchTypes = [.direct]
        widgets.forEach(addSubview)
        addSubview(fade)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Theme.height) }

    var isScrollable: Bool { plan.contentWidth > bounds.width + 0.5 }
    private var maxOffset: CGFloat { max(0, plan.contentWidth - bounds.width) }

    override func layout() {
        super.layout()
        arrange()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        arrange()
    }

    private func arrange() {
        guard bounds.width > 0 else { return }
        let new = StripLayout.plan(widgets.map { ($0.fixedWidth, $0.minWidth) }, available: bounds.width,
                                   minGap: Self.minGap, spread: spread)
        let changed = new != plan
        plan = new
        offset = min(offset, maxOffset)
        place()
        if changed { onLayout?(bounds.width, plan.contentWidth) }
    }

    private func place() {
        for (v, f) in zip(widgets, plan.frames) {
            v.frame = NSRect(x: f.x - offset, y: 0, width: f.width, height: Theme.height)
            v.needsDisplay = true
        }
        fade.frame = bounds
        fade.left = offset > 0.5
        fade.right = offset < maxOffset - 0.5
        fade.needsDisplay = true
    }

    // MARK: Sentuhan: geser kalau bisa digeser dan jari bergerak > 8 pt; selain itu teruskan ke widget.

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

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
        touchStart = (p.x, offset)
        scrolling = false
        target = widgets.first { $0.frame.contains(p) }
        target?.beginPress(at: convert(p, to: target))
    }

    private func move(_ p: NSPoint) {
        guard let start = touchStart else { return }
        let dx = p.x - start.x
        if !scrolling, isScrollable, abs(dx) > 8 {
            scrolling = true
            target?.cancelPress()
            target = nil
        }
        guard scrolling else { return }
        offset = min(maxOffset, max(0, start.offset - dx))
        place()
    }

    private func end(cancelled: Bool) {
        if let t = target { cancelled ? t.cancelPress() : t.endPress() }
        target = nil
        touchStart = nil
        scrolling = false
    }
}

/// Bayangan di tepi strip, tanda masih ada widget di luar layar.
private final class EdgeFadeView: NSView {
    var left = false
    var right = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let w: CGFloat = 28
        if right {
            NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?
                .draw(in: NSRect(x: bounds.maxX - w, y: 0, width: w, height: bounds.height), angle: 0)
        }
        if left {
            NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?
                .draw(in: NSRect(x: 0, y: 0, width: w, height: bounds.height), angle: 180)
        }
    }
}
