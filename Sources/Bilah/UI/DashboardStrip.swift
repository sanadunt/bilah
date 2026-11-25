import AppKit

/// Semua widget dashboard dalam satu item Touch Bar yang lebarnya mengikuti ruang yang tersedia,
/// jadi tidak ada widget yang disembunyikan macOS. Kalau isinya lebih lebar, strip bisa digeser.
/// Strip menerima semua sentuhan dan meneruskan ketukan ke widget di bawah jari.
final class DashboardStripView: NSView {
    static let minGap: CGFloat = 6

    private let widgets: [WidgetView]
    private let mode: SpacingMode
    private let fade = EdgeFadeView()
    private var plan = StripLayout.Plan(frames: [], contentWidth: 0)
    private var offset: CGFloat = 0
    private var touchStart: (x: CGFloat, offset: CGFloat)?
    private var target: WidgetView?
    private var scrolling = false
    private var swiping = false
    private var dragDX: CGFloat = 0

    /// Usap > 50 pt: +1 = halaman berikutnya (usap ke kiri), -1 = sebelumnya (usap ke kanan).
    var onSwipe: ((Int) -> Void)?

    /// Dipanggil tiap tata letak berubah: (lebar tersedia, lebar isi).
    var onLayout: ((CGFloat, CGFloat) -> Void)?

    init(widgets: [WidgetView], mode: SpacingMode = .fill) {
        self.widgets = widgets
        self.mode = mode
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
        let new = StripLayout.plan(
            widgets.map { StripLayout.Item(natural: $0.fixedWidth, min: $0.minWidth, max: $0.stretchMax) },
            available: bounds.width, minGap: Self.minGap, mode: mode)
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
        swiping = false
        dragDX = 0
        target = widgets.first { $0.frame.contains(p) }
        target?.beginPress(at: convert(p, to: target))
    }

    private func move(_ p: NSPoint) {
        guard let start = touchStart else { return }
        let dx = p.x - start.x
        dragDX = dx
        if !scrolling, !swiping, abs(dx) > 8 {
            if isScrollable { scrolling = true } else { swiping = onSwipe != nil }
            if scrolling || swiping {
                target?.cancelPress()
                target = nil
            }
        }
        guard scrolling else { return }
        offset = min(maxOffset, max(0, start.offset - dx))
        place()
    }

    private func end(cancelled: Bool) {
        // Usap ke kiri = halaman berikutnya, ke kanan = sebelumnya. Kalau strip bisa digeser,
        // pindah halaman hanya saat usapan dimulai di ujung dan terus melewatinya.
        if !cancelled, let start = touchStart, abs(dragDX) > 50 {
            let atStart = start.offset <= 0.5 && dragDX > 0
            let atEnd = start.offset >= maxOffset - 0.5 && dragDX < 0
            if swiping || (scrolling && (atStart || atEnd)) { onSwipe?(dragDX < 0 ? 1 : -1) }
        }
        swiping = false
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
