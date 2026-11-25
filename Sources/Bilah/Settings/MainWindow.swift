import AppKit
import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case widgets, general, pomodoro, claude, permissions, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "Widget"
        case .general: "Umum"
        case .pomodoro: "Pomodoro"
        case .claude: "Claude Code"
        case .permissions: "Izin"
        case .updates: "Update"
        case .about: "Tentang"
        }
    }

    var symbol: String {
        switch self {
        case .widgets: "square.grid.3x1.below.line.grid.1x2"
        case .general: "gearshape"
        case .pomodoro: "timer"
        case .claude: "sparkle"
        case .permissions: "lock.shield"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

final class Navigation: ObservableObject {
    @Published var page: Page = .widgets
}

// MARK: - Jendela

final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: SettingsStore
    private let dashboard: DashboardController
    private let updater: Updater
    private let navigation = Navigation()

    init(store: SettingsStore, dashboard: DashboardController, updater: Updater) {
        self.store = store
        self.dashboard = dashboard
        self.updater = updater
    }

    func show(page: Page? = nil) {
        if let page { navigation.page = page }
        if window == nil {
            let root = MainView(store: store, dashboard: dashboard, updater: updater, navigation: navigation)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Bilah"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("BilahMainWindow")
            window = w
        }
        // Selama jendela terbuka Bilah tampil di Dock dan ⌘-Tab; ditutup = kembali jadi app menu bar.
        NSApp.setActivationPolicy(.regular)
        dashboard.previewActive = true
        dashboard.refreshNow()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        dashboard.previewActive = false
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Isi jendela

struct MainView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var dashboard: DashboardController
    @ObservedObject var updater: Updater
    @ObservedObject var navigation: Navigation

    var body: some View {
        VStack(spacing: 0) {
            Header(dashboard: dashboard, updater: updater, navigation: navigation)
            VStack(spacing: 8) {
                BarPreview(settings: store, dashboard: dashboard)
                    .frame(width: BarPreviewView.size.width, height: BarPreviewView.size.height)
                Text("Preview langsung. Widget di sini bisa diklik seperti di Touch Bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            Divider()
            HStack(spacing: 0) {
                List(Page.allCases, selection: Binding(get: { navigation.page }, set: { if let p = $0 { navigation.page = p } })) { page in
                    Label(page.title, systemImage: page.symbol)
                        .badge(page == .updates && updater.updateAvailable ? Text("Baru") : nil)
                        .tag(page)
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: BarPreviewView.size.width + 40, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var detail: some View {
        switch navigation.page {
        case .widgets: WidgetsPage(store: store)
        case .general: GeneralPage(store: store)
        case .pomodoro: PomodoroPage(store: store)
        case .claude: ClaudePage()
        case .permissions: PermissionsPage(dashboard: dashboard)
        case .updates: UpdatesPage(updater: updater)
        case .about: AboutPage()
        }
    }
}

private struct Header: View {
    @ObservedObject var dashboard: DashboardController
    @ObservedObject var updater: Updater
    @ObservedObject var navigation: Navigation

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bilah").font(.title2.weight(.semibold))
                Text("Dashboard Touch Bar · v\(Updater.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !dashboard.available {
                Label("API Touch Bar tidak tersedia di macOS ini", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if updater.updateAvailable, let v = updater.latest?.version {
                Button {
                    navigation.page = .updates
                } label: {
                    Label("Update v\(v) tersedia", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            Button(dashboard.isShown ? "Sembunyikan dari Touch Bar" : "Tampilkan di Touch Bar") {
                dashboard.toggle()
            }
            .disabled(!dashboard.available)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

/// Kerangka halaman: judul + keterangan + isi.
private struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 4)
            content
        }
    }
}

// MARK: Widget

private struct WidgetsPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PageScaffold(title: "Widget",
                     subtitle: "Seret untuk mengubah urutan (atas = kiri). Kalau Touch Bar penuh, widget berprioritas rendah disembunyikan otomatis.") {
            List {
                ForEach(store.order) { kind in
                    WidgetRow(kind: kind, enabled: Binding(get: { store.isEnabled(kind) },
                                                           set: { store.setEnabled(kind, $0) }))
                }
                .onMove { store.order.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
        }
    }
}

private struct WidgetRow: View {
    let kind: WidgetKind
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: kind.tint).opacity(enabled ? 0.22 : 0.08))
                Image(systemName: kind.symbol)
                    .foregroundStyle(Color(nsColor: kind.tint).opacity(enabled ? 1 : 0.4))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).fontWeight(.medium)
                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(enabled ? 1 : 0.55)
            Spacer()
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 5)
    }
}

// MARK: Umum

private struct GeneralPage: View {
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        PageScaffold(title: "Umum", subtitle: "Cara dashboard tampil di Touch Bar.") {
            Form {
                Section("Tampilan") {
                    Toggle("Pakai seluruh lebar Touch Bar (sembunyikan Control Strip)", isOn: $store.hideControlStrip)
                    Toggle("Munculkan lagi dashboard tiap pindah aplikasi", isOn: $store.reassertOnAppSwitch)
                    Toggle("Munculkan dashboard saat sesi Pomodoro habis", isOn: $store.showOnPomodoroEnd)
                }
                Section {
                    Toggle("Buka Bilah otomatis saat login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Login")
                } footer: {
                    Text("Saat dibuka otomatis, Bilah langsung ke Touch Bar tanpa membuka jendela ini.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Gagal: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: Pomodoro

private struct PomodoroPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PageScaffold(title: "Pomodoro",
                     subtitle: "Ketuk widget untuk mulai atau jeda. Saat dijeda, ketuk ↺ untuk reset. Fokus selesai langsung lanjut istirahat.") {
            Form {
                Section("Durasi") {
                    Stepper("Fokus: \(store.focusMinutes) menit", value: $store.focusMinutes, in: 5...120, step: 5)
                    Stepper("Istirahat: \(store.breakMinutes) menit", value: $store.breakMinutes, in: 1...30)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: Claude Code

private struct ClaudePage: View {
    @State private var files = HookConfig.candidateSettingsFiles()
    @State private var installed: [URL: Bool] = [:]
    @State private var sessions = ClaudeStore.loadAll()
    @State private var message: String?
    @State private var copied = false
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        PageScaffold(title: "Claude Code",
                     subtitle: "Bilah membaca status sesi dari hook Claude Code. Pasang hook-nya sekali, lalu widget Claude langsung hidup.") {
            Form {
                Section {
                    if files.isEmpty {
                        Text("Belum ketemu folder Claude Code (~/.claude). Pakai \"Pilih file lain…\".")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(files, id: \.self) { url in
                        HStack {
                            Image(systemName: installed[url] == true ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(installed[url] == true ? .green : .secondary)
                            Text(Self.shortPath(url)).font(.system(.body, design: .monospaced))
                            Spacer()
                            if installed[url] == true {
                                Button("Copot") { run { try HookConfig.uninstall(from: url) } }
                            } else {
                                Button("Pasang") { run { try HookConfig.install(into: url) } }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    HStack {
                        Button("Pilih file lain…", action: pickFile)
                        Button(copied ? "Tersalin ✓" : "Salin konfigurasi manual") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(HookConfig.json(executable: HookConfig.currentExecutable), forType: .string)
                            copied = true
                        }
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Hook")
                } footer: {
                    Text("Bagian lain settings.json tidak diubah, dan versi lamanya dicadangkan sebagai settings.json.bilah-backup. Sesi Claude yang sudah berjalan perlu dibuka ulang supaya hook-nya terbaca.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    if sessions.isEmpty {
                        Text("Belum ada sesi yang terdeteksi.").foregroundStyle(.secondary)
                    }
                    ForEach(sessions, id: \.id) { s in
                        HStack {
                            Circle()
                                .fill(Color(nsColor: s.state.color ?? Theme.secondary))
                                .frame(width: 8, height: 8)
                            Text(s.project).fontWeight(.medium)
                            Text(s.state.title).foregroundStyle(.secondary)
                            Spacer()
                            Text(ClaudeView.ago(s.since)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Button("Bersihkan status sesi") {
                        ClaudeStore.clear()
                        sessions = []
                    }
                } header: {
                    Text("Sesi sekarang")
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: refreshInstalled)
        .onReceive(ticker) { _ in sessions = ClaudeStore.loadAll() }
    }

    private static func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func refreshInstalled() {
        installed = Dictionary(uniqueKeysWithValues: files.map { ($0, HookConfig.isInstalled(in: $0)) })
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            message = nil
        } catch {
            message = "Gagal: \(error.localizedDescription)"
        }
        refreshInstalled()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Pilih settings.json Claude Code"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !files.contains(url) { files.append(url) }
        run { try HookConfig.install(into: url) }
    }
}

// MARK: Izin

private struct PermissionsPage: View {
    @ObservedObject var dashboard: DashboardController
    @State private var axTrusted = SystemActions.hasAccessibility
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        PageScaffold(title: "Izin", subtitle: "Izin macOS yang dipakai Bilah dan untuk apa.") {
            Form {
                Section {
                    PermissionRow(ok: dashboard.available, title: "Touch Bar",
                                  detail: dashboard.available
                                      ? "API Touch Bar tersedia. Pastikan pengaturan Touch Bar memakai \"App Controls\"."
                                      : "API Touch Bar privat tidak ditemukan di macOS ini.")
                    PermissionRow(ok: axTrusted, title: "Aksesibilitas",
                                  detail: "Untuk tombol 🔔 yang membuka Notification Center.") {
                        if !axTrusted {
                            Button("Minta izin") {
                                SystemActions.requestAccessibility()
                                SystemActions.openAccessibilitySettings()
                            }
                        }
                    }
                    PermissionRow(ok: nil, title: "Automation (Spotify / Music)",
                                  detail: "Ditanyakan macOS saat widget Musik pertama kali membaca lagu.") {
                        Button("Buka pengaturan") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } footer: {
                    Text("Bilah ditandatangani sertifikat lokal yang tetap, jadi izin yang sudah diberikan tidak hilang saat update.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onReceive(ticker) { _ in axTrusted = SystemActions.hasAccessibility }
    }
}

private struct PermissionRow<Accessory: View>: View {
    let ok: Bool?
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ok == nil ? "questionmark.circle" : ok! ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ok == nil ? Color.secondary : ok! ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.vertical, 3)
    }
}

extension PermissionRow where Accessory == EmptyView {
    init(ok: Bool?, title: String, detail: String) {
        self.init(ok: ok, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: Update

private struct UpdatesPage: View {
    @ObservedObject var updater: Updater
    @State private var moveError: String?

    var body: some View {
        PageScaffold(title: "Update", subtitle: "Rilis baru diambil dari GitHub \(Updater.repo).") {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Versi terpasang: v\(Updater.currentVersion)").fontWeight(.medium)
                            Text(statusText).foregroundStyle(statusColor)
                        }
                        Spacer()
                        actionButton
                    }
                    if case .downloading(let p) = updater.phase {
                        ProgressView(value: p)
                    }
                    Toggle("Cek update otomatis (tiap 6 jam)", isOn: $updater.autoCheck)
                    if let checked = updater.lastChecked {
                        Text("Terakhir dicek \(checked.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let latest = updater.latest, !latest.notes.isEmpty {
                    Section("Catatan rilis v\(latest.version)") {
                        Text(latest.notes)
                            .font(.callout)
                            .textSelection(.enabled)
                        Link("Lihat di GitHub", destination: latest.page)
                    }
                }

                if !Updater.isInApplications {
                    Section {
                        HStack {
                            Label("Bilah belum ada di folder Applications", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Pindahkan ke Applications") { moveError = Updater.moveToApplications() }
                        }
                        if let moveError { Text(moveError).font(.caption).foregroundStyle(.red) }
                    } footer: {
                        Text("Supaya update otomatis bisa mengganti app dengan aman.").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { if updater.phase == .idle { updater.check() } }
    }

    private var statusText: String {
        switch updater.phase {
        case .idle: "Belum dicek."
        case .checking: "Mengecek GitHub…"
        case .upToDate: "Sudah versi terbaru."
        case .available: "Versi baru tersedia: v\(updater.latest?.version ?? "")"
        case .downloading(let p): "Mengunduh… \(Int(p * 100))%"
        case .installing: "Memasang dan membuka ulang Bilah…"
        case .failed(let m): m
        }
    }

    private var statusColor: Color {
        switch updater.phase {
        case .available: .green
        case .failed: .red
        default: .secondary
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch updater.phase {
        case .available:
            Button("Update sekarang") { updater.install() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Cek sekarang") { updater.check() }
        }
    }
}

// MARK: Tentang

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Bilah").font(.largeTitle.weight(.semibold))
            Text("Versi \(Updater.currentVersion)").foregroundStyle(.secondary)
            Text("Dashboard Touch Bar untuk MacBook Pro: status Claude Code, musik, sistem, Pomodoro, dan kontrol cepat, tampil di semua aplikasi.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Link("github.com/\(Updater.repo)", destination: Updater.repoURL)
            Text("Terinspirasi Pock dan MTMR.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
