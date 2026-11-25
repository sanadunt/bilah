import AppKit
import SwiftUI

/// Meniru cara NSTouchBar menata item: buang prioritas terendah sampai muat, sisa ruang dibagi rata.
enum BarLayout {
    static let width: CGFloat = 1085
    static let controlStripWidth: CGFloat = 180
    static let closeGap: CGFloat = 8
    static let minGap: CGFloat = 6

    static func fit(_ items: [(view: WidgetView, priority: NSTouchBarItem.Priority)],
                    available: CGFloat) -> [WidgetView] {
        var items = items
        while items.reduce(0, { $0 + $1.view.fixedWidth }) + minGap * CGFloat(max(0, items.count - 1)) > available,
              let drop = items.indices.min(by: { items[$0].priority.rawValue < items[$1].priority.rawValue }) {
            items.remove(at: drop)
        }
        return items.map(\.view)
    }

    static func place(_ views: [WidgetView], from x0: CGFloat, to x1: CGFloat, y: CGFloat) {
        let used = views.reduce(0) { $0 + $1.fixedWidth }
        let gap = views.count > 1 ? (x1 - x0 - used) / CGFloat(views.count - 1) : 0
        var x = x0
        for v in views {
            v.frame = NSRect(x: x, y: y, width: v.fixedWidth, height: Theme.height)
            x += v.fixedWidth + gap
        }
    }
}

/// Touch Bar tiruan berisi view widget asli (data live, bisa diklik).
final class BarPreviewView: NSView {
    static let inset: CGFloat = 14
    static let size = NSSize(width: BarLayout.width + inset * 2, height: Theme.height + inset * 2)

    private var signature = ""
    private var showsControlStrip = false

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }

    override func draw(_ dirtyRect: NSRect) {
        Draw.roundedRect(bounds, radius: 14, fill: NSColor(white: 0.11, alpha: 1))
        let bar = bounds.insetBy(dx: Self.inset - 4, dy: Self.inset - 4)
        Draw.roundedRect(bar, radius: 9, fill: .black)
        if showsControlStrip {
            let strip = NSRect(x: Self.inset + BarLayout.width - BarLayout.controlStripWidth, y: Self.inset,
                               width: BarLayout.controlStripWidth, height: Theme.height)
            Draw.roundedRect(strip, radius: Theme.radius, fill: NSColor(white: 1, alpha: 0.05))
            Draw.centered("Control Strip", Theme.font(10, .medium), Theme.faint, x: strip.minX, width: strip.width,
                          centerY: strip.midY, align: .center)
        }
    }

    func reload(settings: SettingsStore, dashboard: DashboardController) {
        let sig = settings.layoutSignature
        guard sig != signature else { return }
        signature = sig
        subviews.forEach { $0.removeFromSuperview() }
        showsControlStrip = !settings.hideControlStrip

        let close = CloseView()
        close.frame = NSRect(x: Self.inset, y: Self.inset, width: close.fixedWidth, height: Theme.height)
        addSubview(close)

        let start = Self.inset + close.fixedWidth + BarLayout.closeGap
        let end = Self.inset + BarLayout.width - (showsControlStrip ? BarLayout.controlStripWidth + BarLayout.closeGap : 0)
        let items = settings.visibleWidgets.map { (view: dashboard.makePreviewView($0), priority: $0.priority) }
        let shown = BarLayout.fit(items, available: end - start)
        BarLayout.place(shown, from: start, to: end, y: Self.inset)
        shown.forEach(addSubview)
        needsDisplay = true
    }
}

struct BarPreview: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore
    let dashboard: DashboardController

    func makeNSView(context: Context) -> BarPreviewView {
        let v = BarPreviewView(frame: NSRect(origin: .zero, size: BarPreviewView.size))
        v.reload(settings: settings, dashboard: dashboard)
        return v
    }

    func updateNSView(_ v: BarPreviewView, context: Context) {
        v.reload(settings: settings, dashboard: dashboard)
    }
}
