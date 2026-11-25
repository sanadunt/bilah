import AppKit
import Darwin
import IOKit.ps

struct BatteryInfo: Equatable {
    var percent: Int
    var charging: Bool
    var pluggedIn: Bool
}

/// Angka sistem dari Mach dan IOKit, tanpa proses tambahan.
final class SystemSampler {
    private let host = mach_host_self()
    private var last: (busy: UInt64, total: UInt64)?

    /// Beban CPU total sejak panggilan sebelumnya (0...1). Panggilan pertama mengembalikan nil.
    func cpuLoad() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { last = (busy, total) }
        guard let l = last, total > l.total, busy >= l.busy else { return nil }
        return Double(busy - l.busy) / Double(total - l.total)
    }

    /// Memori terpakai ala Activity Monitor: app + wired + compressed.
    func memoryUsage() -> Double? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let app = max(0, Int64(vm.internal_page_count) - Int64(vm.purgeable_count))
        let pages = app + Int64(vm.wire_count) + Int64(vm.compressor_page_count)
        let used = Double(pages) * Double(vm_kernel_page_size)
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    func battery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryInfo(percent: current * 100 / max,
                               charging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                               pluggedIn: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

final class SystemWidget: Widget {
    let kind = WidgetKind.system
    private let sampler = SystemSampler()
    private var cpuHistory: [Double] = []
    private var memory: Double?
    private var battery: BatteryInfo?
    private var ticks = 0
    private let views = ViewSet<SystemView>()

    init() { _ = sampler.cpuLoad() }

    func makeView() -> WidgetView {
        let v = SystemView()
        views.add(v)
        push()
        return v
    }

    func tick() {
        if let load = sampler.cpuLoad() {
            cpuHistory.append(load)
            if cpuHistory.count > SystemView.historyLength { cpuHistory.removeFirst() }
        }
        if ticks % 2 == 0 { memory = sampler.memoryUsage() }
        if ticks % 15 == 0 { battery = sampler.battery() }
        ticks += 1
        push()
    }

    private func push() {
        views.forEach { v in
            v.cpuHistory = cpuHistory
            v.memory = memory
            v.battery = battery
            v.needsDisplay = true
        }
    }
}

final class SystemView: WidgetView {
    static let historyLength = 36
    var cpuHistory: [Double] = []
    var memory: Double?
    var battery: BatteryInfo?

    init() { super.init(width: 222, range: 150...360) }
    required init?(coder: NSCoder) { fatalError() }

    override func drawContent(_ b: NSRect) {
        let label = Theme.font(8.5, .semibold)
        let value = Theme.mono(11.5, .semibold)

        // Lebar bebas: baterai 48 pt (hilang kalau < 200 pt), RAM 70 pt, sisanya CPU + grafik.
        let batteryWidth: CGFloat = b.width >= 200 ? 48 : 0
        let ramX = b.width - batteryWidth - 70
        let batteryX = b.width - batteryWidth

        // CPU: angka + grafik garis 36 detik terakhir (grafik hilang kalau terlalu sempit).
        let cpu = cpuHistory.last
        Draw.line("CPU", label, Theme.secondary, x: 9, y: 3.5, width: 40)
        Draw.line(cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", value, cpu.map(Theme.load) ?? Theme.text,
                  x: 9, y: 14, width: 40)
        let sparkWidth = ramX - 46 - 8
        if sparkWidth >= 16 {
            drawSparkline(in: NSRect(x: 46, y: 6, width: sparkWidth, height: 18), color: cpu.map(Theme.load) ?? Theme.green)
        }

        divider(at: ramX, in: b)

        // RAM: angka + cincin.
        Draw.line("RAM", label, Theme.secondary, x: ramX + 8, y: 3.5, width: 40)
        Draw.line(memory.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", value, Theme.text, x: ramX + 8, y: 14, width: 40)
        let ringCenter = NSPoint(x: ramX + 54, y: b.midY)
        Draw.ring(ringCenter, 7, width: 2.4, color: Theme.track)
        Draw.ring(ringCenter, 7, width: 2.4, color: Theme.load(memory ?? 0), to: CGFloat(memory ?? 0))

        guard batteryWidth > 0 else { return }
        divider(at: batteryX, in: b)

        // Baterai.
        guard let bat = battery else {
            Draw.symbol("powerplug.fill", size: 11, weight: .medium, color: Theme.secondary,
                        center: NSPoint(x: batteryX + 24, y: b.midY))
            return
        }
        let color = bat.charging || bat.pluggedIn ? Theme.green : (bat.percent <= 20 ? Theme.red : Theme.text)
        let level = bat.percent > 87 ? "100" : bat.percent > 62 ? "75" : bat.percent > 37 ? "50" : bat.percent > 12 ? "25" : "0"
        Draw.symbol("battery.\(level)percent", size: 12, weight: .regular, color: color, center: NSPoint(x: batteryX + 17, y: 10.5))
        if bat.charging {
            Draw.symbol("bolt.fill", size: 8, weight: .bold, color: Theme.amber, center: NSPoint(x: batteryX + 35, y: 10.5))
        }
        Draw.line("\(bat.percent)%", Theme.mono(10, .semibold), Theme.text, x: batteryX + 1, y: 16, width: 44, align: .center)
    }

    private func divider(at x: CGFloat, in b: NSRect) {
        Draw.roundedRect(NSRect(x: x, y: 7, width: 1, height: b.height - 14), radius: 0.5, fill: Theme.divider)
    }

    private func drawSparkline(in r: NSRect, color: NSColor) {
        let pts = cpuHistory
        guard pts.count > 1 else {
            Draw.roundedRect(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), radius: 0.5, fill: Theme.track)
            return
        }
        let step = r.width / CGFloat(Self.historyLength - 1)
        let x0 = r.maxX - step * CGFloat(pts.count - 1)
        func point(_ i: Int) -> NSPoint {
            NSPoint(x: x0 + step * CGFloat(i), y: r.maxY - r.height * CGFloat(min(1, max(0, pts[i]))))
        }
        let line = NSBezierPath()
        line.move(to: point(0))
        for i in 1..<pts.count { line.line(to: point(i)) }

        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: r.maxX, y: r.maxY))
        area.line(to: NSPoint(x: x0, y: r.maxY))
        area.close()
        NSGradient(starting: color.withAlphaComponent(0.35), ending: color.withAlphaComponent(0.02))?
            .draw(in: area, angle: 90)

        line.lineWidth = 1.3
        line.lineJoinStyle = .round
        color.setStroke()
        line.stroke()
    }
}
