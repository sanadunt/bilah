import AppKit
import QuartzCore

/// Dasar semua tampilan di Touch Bar: kapsul abu-abu, digambar manual, menerima sentuhan langsung.
class WidgetView: NSView {
    var onTap: ((NSPoint) -> Void)?
    private(set) var pressPoint: NSPoint?
    let defaultWidth: CGFloat
    /// Rentang lebar yang boleh diatur pengguna di mode Atur tata letak.
    let widthRange: ClosedRange<CGFloat>
    private let shrinkMin: CGFloat
    /// Lebar yang dipakai sekarang: bawaan, atau pilihan pengguna.
    private(set) var fixedWidth: CGFloat
    /// Lebar terkecil saat dashboard sempit. Hanya menyusut kalau pengguna belum mengatur lebarnya sendiri.
    private(set) var minWidth: CGFloat
    /// Lebar terbesar di mode Isi penuh. Lebar pilihan pengguna jadi ukuran dasar, lalu tetap boleh melebar.
    var stretchMax: CGFloat { widthRange.upperBound }

    var isResizable: Bool { widthRange.lowerBound < widthRange.upperBound }

    /// true = seluruh kapsul menyala saat ditekan. Widget dengan beberapa zona tombol menggambar sorotannya sendiri.
    var highlightsWhole: Bool { true }

    var animating = false {
        didSet { if animating != oldValue { Animator.shared.set(self, animating: animating) } }
    }

    init(width: CGFloat, minWidth: CGFloat? = nil, range: ClosedRange<CGFloat>? = nil) {
        defaultWidth = width
        fixedWidth = width
        shrinkMin = min(width, minWidth ?? width)
        self.minWidth = shrinkMin
        widthRange = range ?? width...width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Theme.height))
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: fixedWidth, height: Theme.height) }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = highlightsWhole && pressPoint != nil
        Draw.pill(bounds, pressed: pressed)
        drawContent(bounds)
    }

    func drawContent(_ b: NSRect) {}

    /// nil = lebar bawaan (boleh menyusut otomatis); angka = pilihan pengguna, dijaga tetap.
    func applyWidth(_ width: CGFloat?) {
        if let width {
            fixedWidth = clampWidth(width)
            minWidth = fixedWidth
        } else {
            fixedWidth = defaultWidth
            minWidth = shrinkMin
        }
        invalidateIntrinsicContentSize()
    }

    func clampWidth(_ w: CGFloat) -> CGFloat { min(widthRange.upperBound, max(widthRange.lowerBound, w)) }

    // MARK: Sentuhan (Touch Bar) dan klik (untuk uji di layar biasa)

    override func touchesBegan(with event: NSEvent) {
        guard let t = event.touches(matching: .began, in: self).first else { return }
        beginPress(at: t.location(in: self))
    }

    override func touchesEnded(with event: NSEvent) { endPress() }
    override func touchesCancelled(with event: NSEvent) { cancelPress() }
    override func mouseDown(with event: NSEvent) { beginPress(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { endPress() }

    // Juga dipanggil DashboardStripView, yang menerima sentuhan atas nama widget di dalamnya.

    func beginPress(at p: NSPoint) {
        pressPoint = p
        needsDisplay = true
    }

    func endPress() {
        guard let p = pressPoint else { return }
        pressPoint = nil
        needsDisplay = true
        onTap?(p)
    }

    func cancelPress() {
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
