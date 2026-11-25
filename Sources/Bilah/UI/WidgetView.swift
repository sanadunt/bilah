import AppKit
import QuartzCore

/// Dasar semua tampilan di Touch Bar: kapsul abu-abu, digambar manual, menerima sentuhan langsung.
class WidgetView: NSView {
    var onTap: ((NSPoint) -> Void)?
    private(set) var pressPoint: NSPoint?
    let fixedWidth: CGFloat

    /// true = seluruh kapsul menyala saat ditekan. Widget dengan beberapa zona tombol menggambar sorotannya sendiri.
    var highlightsWhole: Bool { true }

    var animating = false {
        didSet { if animating != oldValue { Animator.shared.set(self, animating: animating) } }
    }

    init(width: CGFloat) {
        fixedWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Theme.height))
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: fixedWidth, height: Theme.height) }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = highlightsWhole && pressPoint != nil
        Draw.roundedRect(bounds, radius: Theme.radius, fill: pressed ? Theme.pillPressed : Theme.pill)
        drawContent(bounds)
    }

    func drawContent(_ b: NSRect) {}

    // MARK: Sentuhan (Touch Bar) dan klik (untuk uji di layar biasa)

    override func touchesBegan(with event: NSEvent) {
        guard let t = event.touches(matching: .began, in: self).first else { return }
        press(t.location(in: self))
    }

    override func touchesEnded(with event: NSEvent) { release() }
    override func touchesCancelled(with event: NSEvent) { cancel() }
    override func mouseDown(with event: NSEvent) { press(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { release() }

    private func press(_ p: NSPoint) {
        pressPoint = p
        needsDisplay = true
    }

    private func release() {
        guard let p = pressPoint else { return }
        pressPoint = nil
        needsDisplay = true
        onTap?(p)
    }

    private func cancel() {
        pressPoint = nil
        needsDisplay = true
    }
}

/// Satu timer 30 fps untuk semua view yang sedang beranimasi; mati sendiri kalau tidak ada yang butuh.
final class Animator: NSObject {
    static let shared = Animator()
    static var now: CFTimeInterval { CACurrentMediaTime() }

    private let views = NSHashTable<NSView>.weakObjects()
    private var timer: Timer?

    func set(_ view: NSView, animating: Bool) {
        if animating { views.add(view) } else { views.remove(view) }
        if views.count > 0, timer == nil {
            let t = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if views.count == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func tick() {
        for v in views.allObjects { v.needsDisplay = true }
    }
}

/// Kumpulan view lemah milik satu widget: satu di Touch Bar, satu lagi di preview jendela.
final class ViewSet<V: NSView> {
    private let table = NSHashTable<V>.weakObjects()
    func add(_ v: V) { table.add(v) }
    func forEach(_ body: (V) -> Void) { table.allObjects.forEach(body) }
}
