import AppKit
import ApplicationServices

/// Lebar ruang Touch Bar untuk Bilah, diukur dari Touch Bar asli lalu disimpan.
/// Tiap bar Bilah adalah SATU item selebar ruang ini, jadi macOS tidak pernah perlu membuang item
/// (dulu yang terbuang justru tombol tutup).
enum TouchBarRegion {
    private static func key(_ hideControlStrip: Bool) -> String {
        hideControlStrip ? "touchBarRegionFull" : "touchBarRegionWithStrip"
    }

    /// Lebar yang dipakai sekarang. Belum pernah diukur: kalau bisa mengukur, minta selebar mungkin dulu
    /// (Touch Bar memotongnya, lalu hasil ukur dipakai); kalau tidak bisa, pakai tebakan aman.
    static func width(hideControlStrip: Bool) -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: key(hideControlStrip))
        if saved > 200 { return saved }
        if SystemActions.hasAccessibility { return BarLayout.width }
        return hideControlStrip ? 1004 : 800
    }

    static func save(_ width: CGFloat, hideControlStrip: Bool) {
        UserDefaults.standard.set(Double(width), forKey: key(hideControlStrip))
    }

    /// Baca lebar bar Bilah yang benar-benar tampil, lewat Accessibility (atribut AXFunctionRowTopLevelElements).
    /// Dijalankan di thread latar: permintaan AX ke proses sendiri dilayani main thread.
    static func measure(_ done: @escaping (CGFloat?) -> Void) {
        guard SystemActions.hasAccessibility else { done(nil); return }
        DispatchQueue.global(qos: .utility).async {
            let app = AXUIElementCreateApplication(getpid())
            AXUIElementSetMessagingTimeout(app, 1)
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(app, "AXFunctionRowTopLevelElements" as CFString, &value)
            let widths = (value as? [AXUIElement] ?? []).compactMap { el -> CGFloat? in
                var raw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &raw) == .success, let raw,
                      CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
                var size = CGSize.zero
                AXValueGetValue(raw as! AXValue, .cgSize, &size)
                return size.width
            }
            let width = widths.max()
            DispatchQueue.main.async { done(width) }
        }
    }
}

/// Wadah satu item Touch Bar: [awal] [isi yang melebar] [akhir], selebar ruang Touch Bar.
final class BarContainerView: NSView {
    private let leading: NSView?
    private let content: NSView
    private let trailing: NSView?
    private var widthConstraint: NSLayoutConstraint!
    private static let edgeWidth: CGFloat = 30
    private static let gap: CGFloat = 8

    init(leading: NSView? = nil, content: NSView, trailing: NSView? = nil, width: CGFloat) {
        self.leading = leading
        self.content = content
        self.trailing = trailing
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Theme.height))
        [leading, content, trailing].compactMap { $0 }.forEach(addSubview)
        widthConstraint = widthAnchor.constraint(equalToConstant: width)
        widthConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: widthConstraint.constant, height: Theme.height) }

    var width: CGFloat {
        get { widthConstraint.constant }
        set {
            guard abs(newValue - widthConstraint.constant) > 0.5 else { return }
            widthConstraint.constant = newValue
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        var x0: CGFloat = 0
        var x1 = bounds.width
        if let leading {
            let w = (leading as? WidgetView)?.fixedWidth ?? Self.edgeWidth
            leading.frame = NSRect(x: 0, y: 0, width: w, height: Theme.height)
            x0 = w + Self.gap
        }
        if let trailing {
            trailing.frame = NSRect(x: x1 - Self.edgeWidth, y: 0, width: Self.edgeWidth, height: Theme.height)
            x1 -= Self.edgeWidth + Self.gap
        }
        content.frame = NSRect(x: x0, y: 0, width: max(0, x1 - x0), height: Theme.height)
    }
}
