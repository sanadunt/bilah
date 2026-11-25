import AppKit
import SwiftUI

enum BarLayout {
    static let width: CGFloat = 1085
    static let controlStripWidth: CGFloat = 180
    static let closeGap: CGFloat = 8
}

/// Touch Bar tiruan berisi strip dashboard yang sama persis dengan di Touch Bar (data live, bisa diklik dan digeser).
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
        let strip = DashboardStripView(widgets: settings.visibleWidgets.map(dashboard.makePreviewView))
        strip.frame = NSRect(x: start, y: Self.inset, width: end - start, height: Theme.height)
        addSubview(strip)
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
