import AppKit
import SwiftUI

enum BarLayout {
    static let width: CGFloat = 1085
    static let controlStripWidth: CGFloat = 180
    static let closeGap: CGFloat = 8
}

/// Touch Bar tiruan berisi strip dashboard yang sama persis dengan di Touch Bar (data live, bisa diklik dan digeser).
/// Di mode Atur tata letak, isinya diganti kanvas edit.
final class BarPreviewView: NSView {
    static let inset: CGFloat = 14
    /// Selebar ruang Touch Bar yang terukur, supaya preview sama persis dengan aslinya.
    static var barWidth: CGFloat { min(BarLayout.width, TouchBarRegion.width(hideControlStrip: true)) }

    static func size(editing: Bool) -> NSSize {
        NSSize(width: barWidth + inset * 2,
               height: Theme.height + inset * 2 + (editing ? LayoutEditCanvas.labelHeight : 0))
    }

    private var signature = ""
    private var showsControlStrip = false
    private var editing = false

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size(editing: editing) }

    private var widgetWidth: CGFloat {
        Self.barWidth - (showsControlStrip ? BarLayout.controlStripWidth + BarLayout.closeGap : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        Draw.roundedRect(bounds, radius: 14, fill: NSColor(white: 0.11, alpha: 1))
        if showsControlStrip {
            let strip = NSRect(x: Self.inset + Self.barWidth - BarLayout.controlStripWidth, y: Self.inset,
                               width: BarLayout.controlStripWidth, height: Theme.height)
            Draw.roundedRect(strip.insetBy(dx: -4, dy: -4), radius: 9, fill: .black)
            Draw.roundedRect(strip, radius: Theme.radius, fill: NSColor(white: 1, alpha: 0.05))
            Draw.centered("Control Strip", Theme.font(10, .medium), Theme.faint, x: strip.minX, width: strip.width,
                          centerY: strip.midY, align: .center)
        }
        guard !editing else { return } // kanvas edit menggambar Touch Bar-nya sendiri
        let bar = NSRect(x: Self.inset, y: Self.inset, width: widgetWidth, height: Theme.height)
        Draw.roundedRect(bar.insetBy(dx: -4, dy: -4), radius: 9, fill: .black)
    }

    func reload(settings: SettingsStore, dashboard: DashboardController, editor: LayoutEditorState) {
        let sig = settings.layoutSignature + "|edit=\(editor.editing)"
        guard sig != signature else { return }
        signature = sig
        subviews.forEach { $0.removeFromSuperview() }
        showsControlStrip = !settings.hideControlStrip
        editing = editor.editing
        invalidateIntrinsicContentSize()

        let width = widgetWidth
        if editing {
            let items = settings.visibleWidgets.map { (kind: $0, view: dashboard.makePreviewView($0)) }
            let canvas = LayoutEditCanvas(items: items, barWidth: width)
            canvas.frame = NSRect(x: Self.inset, y: Self.inset, width: width,
                                  height: Theme.height + LayoutEditCanvas.labelHeight)
            canvas.onCommit = { order, widths in
                settings.setVisibleOrder(order)
                for (kind, w) in widths { settings.widgetWidths[kind.rawValue] = Double(w) }
            }
            canvas.onRemove = { settings.setEnabled($0, false) }
            canvas.onResetWidth = { settings.widgetWidths[$0.rawValue] = nil }
            canvas.onMetrics = { used, available in
                DispatchQueue.main.async {
                    editor.used = used
                    editor.available = available
                }
            }
            addSubview(canvas)
        } else {
            let strip = DashboardStripView(widgets: settings.visibleWidgets.map(dashboard.makePreviewView),
                                           mode: settings.spacing)
            let bar = BarContainerView(leading: CloseView(), content: strip, width: width)
            bar.frame = NSRect(x: Self.inset, y: Self.inset, width: width, height: Theme.height)
            addSubview(bar)
            bar.layoutSubtreeIfNeeded()
        }
        needsDisplay = true
    }
}

struct BarPreview: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var editor: LayoutEditorState
    let dashboard: DashboardController

    func makeNSView(context: Context) -> BarPreviewView {
        let v = BarPreviewView(frame: NSRect(origin: .zero, size: BarPreviewView.size(editing: editor.editing)))
        v.reload(settings: settings, dashboard: dashboard, editor: editor)
        return v
    }

    func updateNSView(_ v: BarPreviewView, context: Context) {
        v.reload(settings: settings, dashboard: dashboard, editor: editor)
    }
}

/// Baris di bawah preview: tombol masuk mode edit, atau toolbar edit beserta meteran kapasitas.
struct LayoutToolbar: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var editor: LayoutEditorState

    private var hidden: [WidgetKind] { store.order.filter { !store.isEnabled($0) } }

    var body: some View {
        if editor.editing {
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    capacity
                    Spacer()
                    Picker("Jarak", selection: $store.spacing) {
                        ForEach(SpacingMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                    .help("Isi penuh: widget melebar mengisi sisa ruang. Sebar merata: sisa ruang jadi jarak. Rapat: semua di kiri.")
                    Menu {
                        ForEach(hidden) { kind in
                            Button(kind.title) { store.setEnabled(kind, true) }
                        }
                    } label: {
                        Label("Tambah widget", systemImage: "plus")
                    }
                    .disabled(hidden.isEmpty)
                    .fixedSize()
                    Button("Ukuran bawaan") { store.widgetWidths = [:] }
                        .disabled(store.widgetWidths.isEmpty)
                    Button("Selesai") { editor.editing = false }
                        .buttonStyle(.borderedProminent)
                }
                Text("Seret widget untuk menyusun · tarik garis di tepi kanannya untuk mengubah lebar · klik dua kali untuk ukuran bawaan · × untuk menyembunyikan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                Text("Preview langsung. Widget di sini bisa diklik seperti di Touch Bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    editor.editing = true
                } label: {
                    Label("Atur tata letak", systemImage: "rectangle.3.group")
                }
                .controlSize(.small)
            }
        }
    }

    private var capacity: some View {
        let used = Int(editor.used.rounded())
        let available = Int(editor.available.rounded())
        let over = used - available
        return HStack(spacing: 8) {
            Image(systemName: over > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(over > 0 ? .orange : .green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Terpakai \(used) / \(available) pt").fontWeight(.medium).monospacedDigit()
                Text(over > 0 ? "\(over) pt lebih, sisanya bisa digeser di Touch Bar"
                     : store.spacing == .fill ? "Sisa \(-over) pt diisi otomatis" : "Sisa \(-over) pt")
                    .font(.caption)
                    .foregroundStyle(over > 0 ? .orange : .secondary)
            }
            ProgressView(value: min(1, Double(used) / Double(max(1, available))))
                .tint(over > 0 ? .orange : .green)
                .frame(width: 110)
        }
    }
}
