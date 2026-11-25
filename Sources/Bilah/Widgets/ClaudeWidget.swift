import AppKit

final class ClaudeWidget: Widget {
    let kind = WidgetKind.claude
    var ticksWhenHidden: Bool { true }

    private(set) var sessions: [ClaudeSession] = []
    private var focusID: String?
    private let views = ViewSet<ClaudeView>()

    /// Status paling penting untuk titik di ikon Control Strip. "Selesai" hanya tampil 15 menit.
    var headline: ClaudeState? {
        guard let top = sessions.first else { return nil }
        if top.state == .done && Date().timeIntervalSince1970 - top.updated > 15 * 60 { return nil }
        return top.state == .idle ? nil : top.state
    }

    func makeView() -> WidgetView {
        let v = ClaudeView()
        v.onTap = { [weak self] _ in self?.cycle() }
        views.add(v)
        push()
        return v
    }

    func tick() {
        sessions = ClaudeStore.loadAll()
        push()
    }

    /// Ketuk = pindah ke sesi berikutnya.
    private func cycle() {
        guard sessions.count > 1 else { return }
        let i = sessions.firstIndex { $0.id == focusID } ?? 0
        focusID = sessions[(i + 1) % sessions.count].id
        push()
    }

    private func push() {
        if !sessions.contains(where: { $0.id == focusID }) { focusID = sessions.first?.id }
        views.forEach { $0.update(sessions: sessions, focusID: focusID) }
    }
}

final class ClaudeView: WidgetView {
    private var sessions: [ClaudeSession] = []
    private var focus = 0

    init() { super.init(width: 200, minWidth: 156) }
    required init?(coder: NSCoder) { fatalError() }

    func update(sessions: [ClaudeSession], focusID: String?) {
        self.sessions = sessions
        focus = sessions.firstIndex { $0.id == focusID } ?? 0
        animating = sessions.contains { $0.state == .working || $0.state == .waiting }
        needsDisplay = true
    }

    override func drawContent(_ b: NSRect) {
        let t = Animator.now
        let icon = NSPoint(x: 17, y: b.midY)

        guard let s = sessions[safe: focus] else {
            Draw.symbol("sparkle", size: 11, weight: .medium, color: Theme.faint, center: icon)
            Draw.centered("Claude lagi santai", Theme.font(11, .medium), Theme.secondary,
                          x: 32, width: b.width - 40, centerY: b.midY)
            return
        }

        // Kalau ada sesi yang minta izin, seluruh kapsul berdenyut kuning walau yang difokus sesi lain.
        if sessions.contains(where: { $0.state == .waiting }) {
            let phase = CGFloat((sin(t * 4) + 1) / 2)
            let border = NSBezierPath(roundedRect: b.insetBy(dx: 0.75, dy: 0.75), xRadius: Theme.radius, yRadius: Theme.radius)
            border.lineWidth = 1.5
            Theme.amber.withAlphaComponent(0.25 + 0.55 * phase).setStroke()
            border.stroke()
        }

        switch s.state {
        case .working:
            Draw.ring(icon, 6.5, width: 2, color: Theme.track)
            let start = CGFloat((t * 1.4).truncatingRemainder(dividingBy: 1))
            Draw.ring(icon, 6.5, width: 2, color: Theme.coral, from: start, to: start + 0.3)
            if start + 0.3 > 1 { Draw.ring(icon, 6.5, width: 2, color: Theme.coral, from: 0, to: start + 0.3 - 1) }
        case .waiting:
            let phase = CGFloat((sin(t * 4) + 1) / 2)
            Draw.circle(icon, 4 + 4 * phase, Theme.amber.withAlphaComponent(0.35 * (1 - phase)))
            Draw.circle(icon, 4, Theme.amber)
        case .done:
            Draw.symbol("checkmark.circle.fill", size: 13, weight: .semibold, color: Theme.green, center: icon)
        case .idle:
            Draw.symbol("sparkle", size: 11, weight: .medium, color: Theme.secondary, center: icon)
        }

        let multi = sessions.count > 1
        let textWidth = b.width - 32 - (multi ? 30 : 8)
        Draw.line(s.state.title, Theme.font(11, .semibold), s.state.color ?? Theme.text, x: 32, y: 3, width: textWidth)
        Draw.line("\(s.project) · \(Self.ago(s.since))", Theme.font(9.5), Theme.secondary, x: 32, y: 16, width: textWidth)

        if multi {
            // Titik per sesi (maks 5), yang difokus lebih besar.
            let shown = Array(sessions.prefix(5))
            let step: CGFloat = 5.5
            let startY = b.midY - step * CGFloat(shown.count - 1) / 2
            for (i, other) in shown.enumerated() {
                let c = NSPoint(x: b.maxX - 12, y: startY + step * CGFloat(i))
                Draw.circle(c, i == focus ? 2.4 : 1.6, other.state.color ?? Theme.secondary)
            }
        }
    }

    static func ago(_ ts: Double) -> String {
        let s = Date().timeIntervalSince1970 - ts
        if s < 60 { return "baru saja" }
        if s < 3600 { return "\(Int(s / 60)) mnt" }
        return "\(Int(s / 3600)) jam"
    }
}
