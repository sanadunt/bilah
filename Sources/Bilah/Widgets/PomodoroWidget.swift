import AppKit

enum PomodoroPhase {
    case focus, rest

    var color: NSColor { self == .focus ? Theme.coral : Theme.green }
}

enum PomodoroRunState { case idle, running, paused }

struct PomodoroDisplay {
    var phase: PomodoroPhase = .focus
    var state: PomodoroRunState = .idle
    var remaining: TimeInterval = 25 * 60
    var total: TimeInterval = 25 * 60
    var flashUntil: Date = .distantPast
}

/// Ketuk: mulai / jeda / lanjut. Saat dijeda, ketuk ikon ↺ di kanan untuk reset.
/// Fokus selesai → otomatis istirahat; istirahat selesai → kembali siap fokus.
final class PomodoroWidget: Widget {
    private enum Run {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
    }

    let kind = WidgetKind.pomodoro
    var ticksWhenHidden: Bool { true }
    /// Dipanggil saat satu fase habis (dashboard memakainya untuk muncul sendiri).
    var onFinish: (() -> Void)?

    private let settings: SettingsStore
    private var phase = PomodoroPhase.focus
    private var run = Run.idle
    private var flashUntil = Date.distantPast
    private let views = ViewSet<PomodoroView>()

    init(settings: SettingsStore) { self.settings = settings }

    private var total: TimeInterval {
        TimeInterval(phase == .focus ? settings.focusMinutes : settings.breakMinutes) * 60
    }

    func makeView() -> WidgetView {
        let v = PomodoroView()
        v.onTap = { [weak self, weak v] p in
            guard let self, let v else { return }
            self.tap(onReset: p.x > v.bounds.width - PomodoroView.resetZone)
        }
        views.add(v)
        push()
        return v
    }

    func tick() {
        if case .running(let end) = run, end <= Date() { finish() }
        push()
    }

    private func tap(onReset: Bool) {
        let now = Date()
        switch run {
        case .idle: run = .running(end: now + total)
        case .running(let end): run = .paused(remaining: end.timeIntervalSince(now))
        case .paused(let remaining):
            if onReset {
                run = .idle
                phase = .focus
            } else {
                run = .running(end: now + remaining)
            }
        }
        push()
    }

    private func finish() {
        flashUntil = Date() + 6
        if phase == .focus {
            phase = .rest
            run = .running(end: Date() + total)
        } else {
            phase = .focus
            run = .idle
        }
        onFinish?()
    }

    private func push() {
        var d = PomodoroDisplay(phase: phase, total: total, flashUntil: flashUntil)
        switch run {
        case .idle:
            d.state = .idle
            d.remaining = total
        case .running(let end):
            d.state = .running
            d.remaining = max(0, end.timeIntervalSinceNow)
        case .paused(let r):
            d.state = .paused
            d.remaining = r
        }
        views.forEach { $0.display = d }
    }
}

final class PomodoroView: WidgetView {
    static let resetZone: CGFloat = 26

    var display = PomodoroDisplay() {
        didSet {
            animating = display.flashUntil > Date()
            needsDisplay = true
        }
    }

    override var highlightsWhole: Bool { false }

    init() { super.init(width: 114, range: 100...190) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        let d = display
        let color = d.phase.color
        let onReset = d.state == .paused && (pressPoint.map { $0.x > b.width - Self.resetZone } ?? false)

        if pressPoint != nil && !onReset {
            Draw.roundedRect(b, radius: Theme.radius, fill: Theme.pillPressed)
        }
        if d.flashUntil > Date() {
            let a = 0.15 + 0.2 * CGFloat((sin(Animator.now * 8) + 1) / 2)
            Draw.roundedRect(b, radius: Theme.radius, fill: color.withAlphaComponent(a))
        }

        let c = NSPoint(x: 17, y: b.midY)
        Draw.ring(c, 8.5, width: 2.5, color: Theme.track)
        if d.state != .idle, d.total > 0 {
            Draw.ring(c, 8.5, width: 2.5, color: color, to: CGFloat(1 - d.remaining / d.total))
        }
        switch d.state {
        case .idle: Draw.symbol("play.fill", size: 6.5, weight: .bold, color: color, center: NSPoint(x: c.x + 0.7, y: c.y))
        case .paused: Draw.symbol("pause.fill", size: 6, weight: .bold, color: Theme.secondary, center: c)
        case .running: break
        }

        let secs = Int(d.remaining.rounded(.up))
        let time = String(format: "%02d:%02d", secs / 60, secs % 60)
        Draw.line(time, Theme.mono(13, .semibold), d.state == .paused ? Theme.secondary : Theme.text, x: 33, y: 2, width: 64)

        let label: String
        switch (d.state, d.phase) {
        case (.idle, _): label = "Siap fokus"
        case (.paused, _): label = "Dijeda"
        case (.running, .focus): label = "Fokus"
        case (.running, .rest): label = "Istirahat"
        }
        Draw.line(label, Theme.font(9, .medium), d.state == .running ? color : Theme.secondary, x: 33, y: 17, width: 64)

        if d.state == .paused {
            let rc = NSPoint(x: b.width - 14, y: b.midY)
            if onReset { Draw.circle(rc, 11, Theme.pillPressed) }
            Draw.symbol("arrow.counterclockwise", size: 10, weight: .bold, color: Theme.text, center: rc)
        }
    }
}
