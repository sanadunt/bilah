import AppKit
import Combine

/// Status mode Atur tata letak, dibagi antara preview (AppKit) dan toolbar (SwiftUI).
final class LayoutEditorState: ObservableObject {
    @Published var editing = false
    /// Terpisah supaya angka yang berubah saat menyeret hanya menggambar ulang meteran kapasitas.
    let metrics = LayoutMetrics()
}

/// Lebar isi (widget + jarak minimum) dan ruang yang tersedia untuk widget, dalam pt.
final class LayoutMetrics: ObservableObject {
    @Published private(set) var used: CGFloat = 0
    @Published private(set) var available: CGFloat = 0

    func set(used: CGFloat, available: CGFloat) {
        if used != self.used { self.used = used }
        if available != self.available { self.available = available }
    }
}

/// Kanvas edit: widget asli (data live) yang bisa diseret untuk menyusun, ditarik tepi kanannya untuk mengubah lebar,
/// diklik dua kali untuk kembali ke ukuran bawaan, dan × untuk disembunyikan.
/// Kalau isinya melebihi Touch Bar, kanvas mengecil supaya semuanya tetap terlihat, dengan garis batas dan zona merah.
final class LayoutEditCanvas: NSView {
    static let labelHeight: CGFloat = 20
    static let gap: CGFloat = 6
    static let start: CGFloat = 30 + 8

    private enum Drag {
        case move(index: Int, grab: CGFloat, x: CGFloat)
        case resize(index: Int)
    }

    private var items: [(kind: WidgetKind, view: WidgetView)]
    private let close = CloseView()
    private let overlay = EditOverlay()
    private let barWidth: CGFloat
    private var drag: Drag?
    private var insertion: Int?
    private var resized: Set<WidgetKind> = []
    private var contentRight: CGFloat = 0
    private var reported: (used: CGFloat, available: CGFloat)?

    var onCommit: (([WidgetKind], [WidgetKind: CGFloat]) -> Void)?
    var onRemove: ((WidgetKind) -> Void)?
    var onResetWidth: ((WidgetKind) -> Void)?
    /// Langsung dipanggil sekali saat dipasang, lalu tiap tata letak berubah.
    var onMetrics: ((_ used: CGFloat, _ available: CGFloat) -> Void)? {
        didSet { reported = nil; reportMetrics() }
    }

    /// Hanya kalau angkanya berubah, dan tidak selama menyeret: tiap perubahan teks meteran memicu tata letak ulang
    /// halaman SwiftUI. Label lebar di bawah tiap widget sudah ikut berubah langsung; meteran menyusul saat dilepas.
    private func reportMetrics() {
        guard drag == nil, let onMetrics else { return }
        let now = (used: contentRight - Self.start, available: barWidth - Self.start)
        guard reported.map({ $0.used != now.used || $0.available != now.available }) ?? true else { return }
        reported = now
        onMetrics(now.used, now.available)
    }

    init(items: [(kind: WidgetKind, view: WidgetView)], barWidth: CGFloat) {
        self.items = items
        self.barWidth = barWidth
        super.init(frame: NSRect(x: 0, y: 0, width: barWidth, height: Theme.height + Self.labelHeight))
        close.frame = NSRect(x: 0, y: 0, width: close.fixedWidth, height: Theme.height)
        addSubview(close)
        // Widget di kanvas edit dibekukan: tanpa animasi 30 fps (peliharaan, equalizer, dll.) supaya menyeret tetap ringan.
        items.forEach { $0.view.frozen = true; addSubview($0.view) }
        // Frame diatur manual. Tanpa ini, tiap setFrame saat menyeret menandai constraint autoresizing kotor,
        // dan NavigationSplitView menghitung ulang ukuran minimum seluruh halaman di tiap gerakan mouse.
        subviews.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        overlay.canvas = self
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        relayout(rescale: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: Tata letak

    private func width(_ i: Int) -> CGFloat { items[i].view.fixedWidth }

    /// Susun rapat dari kiri. Saat menyeret, widget yang diseret mengikuti kursor dan yang lain memberi celah.
    private func relayout(rescale: Bool) {
        var dragged: Int?
        var draggedX: CGFloat = 0
        if case .move(let i, _, let x) = drag {
            dragged = i
            draggedX = x
        }

        // Tentukan celah sisipan dari posisi tengah widget yang diseret.
        if let d = dragged {
            let center = draggedX + width(d) / 2
            var x = Self.start
            var slot = 0
            for i in items.indices where i != d {
                if x + width(i) / 2 < center { slot += 1 }
                x += width(i) + Self.gap
            }
            insertion = slot
        } else {
            insertion = nil
        }

        var x = Self.start
        var slot = 0
        for i in items.indices where i != dragged {
            if slot == insertion, let d = dragged { x += width(d) + Self.gap }
            items[i].view.frame = NSRect(x: x, y: 0, width: width(i), height: Theme.height)
            x += width(i) + Self.gap
            slot += 1
        }
        if let d = dragged {
            if slot == insertion { x += width(d) + Self.gap }
            items[d].view.frame = NSRect(x: draggedX, y: 0, width: width(d), height: Theme.height)
            // Naikkan ke atas sekali saja saat mulai diseret, bukan di tiap gerakan mouse.
            if subviews.count >= 2, subviews[subviews.count - 2] !== items[d].view {
                addSubview(items[d].view, positioned: .below, relativeTo: overlay)
            }
        }
        contentRight = x - Self.gap
        if rescale { rescaleToFit() }
        overlay.frame = bounds
        overlay.needsDisplay = true
        needsDisplay = true
        if drag == nil { window?.invalidateCursorRects(for: self) }
        reportMetrics()
    }

    /// Kalau isi lebih lebar dari Touch Bar, perkecil skala kanvas supaya semuanya tetap kelihatan.
    private func rescaleToFit() {
        let needed = max(barWidth, contentRight + 12)
        let k = needed / frame.width
        setBoundsSize(NSSize(width: frame.width * k, height: frame.height * k))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rescaleToFit()
        overlay.frame = bounds
    }

    // MARK: Gambar (latar)

    override func draw(_ dirtyRect: NSRect) {
        let bar = NSRect(x: 0, y: 0, width: barWidth, height: Theme.height)
        Draw.roundedRect(bar.insetBy(dx: -4, dy: -4), radius: 9, fill: .black)
        guard contentRight > barWidth else { return }
        // Zona di luar Touch Bar: harus digeser untuk dilihat.
        let over = NSRect(x: barWidth, y: -4, width: contentRight - barWidth + 8, height: Theme.height + 8)
        Draw.roundedRect(over, radius: 6, fill: Theme.red.withAlphaComponent(0.14))
    }

    // MARK: Gambar (di atas widget)

    fileprivate func drawOverlay() {
        let labelFont = Theme.font(10, .medium)
        for (i, item) in items.enumerated() {
            let f = item.view.frame
            let active: Bool = {
                switch drag {
                case .move(let d, _, _), .resize(let d): return d == i
                case nil: return false
                }
            }()
            if active {
                let outline = NSBezierPath(roundedRect: f.insetBy(dx: -1.5, dy: -1.5), xRadius: Theme.radius + 1.5,
                                           yRadius: Theme.radius + 1.5)
                outline.lineWidth = 2
                Theme.teal.setStroke()
                outline.stroke()
            }
            // Pegangan ubah lebar di tepi kanan.
            if item.view.isResizable {
                Draw.roundedRect(NSRect(x: f.maxX - 5, y: f.midY - 8, width: 3, height: 16), radius: 1.5,
                                 fill: Theme.text.withAlphaComponent(active ? 1 : 0.55))
            }
            // Tombol × untuk menyembunyikan.
            let badge = NSPoint(x: f.maxX - 6, y: 6)
            Draw.circle(badge, 6.5, NSColor(white: 0.25, alpha: 1))
            Draw.symbol("xmark", size: 6.5, weight: .bold, color: Theme.text, center: badge)
            // Nama + lebar di bawah widget.
            let text = "\(item.kind.shortTitle) · \(Int(f.width.rounded())) pt"
            Draw.line(text, labelFont, active ? Theme.teal : Theme.secondary, x: f.minX, y: Theme.height + 5,
                      width: f.width, align: .center)
        }
        // Garis batas Touch Bar.
        if contentRight > barWidth {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: barWidth + 2, y: -6))
            line.line(to: NSPoint(x: barWidth + 2, y: Theme.height + 6))
            line.lineWidth = 2
            line.setLineDash([4, 3], count: 2, phase: 0)
            Theme.red.setStroke()
            line.stroke()
            // Tulisan hanya kalau zona luapan cukup lebar, supaya tidak menimpa label widget.
            if contentRight - barWidth >= 90 {
                Draw.line("di luar Touch Bar", Theme.font(9, .semibold), Theme.red, x: barWidth + 8, y: -1, width: 120)
            }
        }
    }

    // MARK: Mouse

    private enum Hit {
        case remove(Int), resize(Int), move(Int)
    }

    private func hit(_ p: NSPoint) -> Hit? {
        for (i, item) in items.enumerated().reversed() {
            let f = item.view.frame
            let badge = NSPoint(x: f.maxX - 6, y: 6)
            if hypot(p.x - badge.x, p.y - badge.y) <= 8 { return .remove(i) }
            if item.view.isResizable, p.x >= f.maxX - 9, p.x <= f.maxX + 4, p.y >= -4, p.y <= Theme.height + 4 {
                return .resize(i)
            }
            if f.insetBy(dx: 0, dy: -4).contains(p) { return .move(i) }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let h = hit(p) else { return }
        switch h {
        case .remove(let i):
            onRemove?(items[i].kind)
        case .resize(let i):
            drag = .resize(index: i)
        case .move(let i):
            if event.clickCount == 2, items[i].view.isResizable {
                onResetWidth?(items[i].kind)
                return
            }
            drag = .move(index: i, grab: p.x - items[i].view.frame.minX, x: items[i].view.frame.minX)
            NSCursor.closedHand.push()
        }
        relayout(rescale: false)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch drag {
        case .resize(let i):
            let view = items[i].view
            let w = view.clampWidth((max(0, p.x - view.frame.minX) / 2).rounded() * 2)
            view.applyWidth(w)
            resized.insert(items[i].kind)
            relayout(rescale: false)
        case .move(let i, let grab, _):
            drag = .move(index: i, grab: grab, x: max(Self.start - 12, p.x - grab))
            relayout(rescale: false)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else { return }
        if case .move(let i, _, _) = current {
            NSCursor.pop()
            if let slot = insertion {
                let moved = items.remove(at: i)
                items.insert(moved, at: min(slot, items.count))
            }
        }
        drag = nil
        relayout(rescale: true)
        var widths: [WidgetKind: CGFloat] = [:]
        for item in items where resized.contains(item.kind) { widths[item.kind] = item.view.fixedWidth }
        resized.removeAll()
        onCommit?(items.map(\.kind), widths)
    }

    override func resetCursorRects() {
        for item in items {
            let f = item.view.frame
            addCursorRect(f, cursor: .openHand)
            if item.view.isResizable {
                addCursorRect(NSRect(x: f.maxX - 9, y: -4, width: 13, height: Theme.height + 8), cursor: .resizeLeftRight)
            }
        }
    }
}

/// Lapisan teratas kanvas: pegangan, ×, label, dan garis batas digambar di atas widget.
private final class EditOverlay: NSView {
    weak var canvas: LayoutEditCanvas?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { canvas?.drawOverlay() }
}
