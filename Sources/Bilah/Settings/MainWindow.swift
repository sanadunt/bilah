import AppKit
import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case widgets, shortcuts, music, pets, general, pomodoro, claude, permissions, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "Widget"
        case .shortcuts: "Pintasan"
        case .music: "Musik"
        case .pets: "Peliharaan"
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
        case .shortcuts: "square.grid.2x2"
        case .music: "music.note"
        case .pets: "pawprint.fill"
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
    private let editor = LayoutEditorState()

    init(store: SettingsStore, dashboard: DashboardController, updater: Updater) {
        self.store = store
        self.dashboard = dashboard
        self.updater = updater
    }

    func show(page: Page? = nil) {
        if let page { navigation.page = page }
        if window == nil {
            let root = MainView(store: store, dashboard: dashboard, updater: updater, navigation: navigation,
                                editor: editor)
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
        editor.editing = false
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
    @ObservedObject var editor: LayoutEditorState

    var body: some View {
        VStack(spacing: 0) {
            Header(dashboard: dashboard, updater: updater, navigation: navigation)
            VStack(spacing: 10) {
                let size = BarPreviewView.size(editing: editor.editing)
                BarPreview(settings: store, editor: editor, dashboard: dashboard)
                    .frame(width: size.width, height: size.height)
                LayoutToolbar(store: store, editor: editor)
                    .frame(width: size.width)
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
        .frame(width: BarPreviewView.size(editing: false).width + 40, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var detail: some View {
        switch navigation.page {
        case .widgets: WidgetsPage(store: store)
        case .shortcuts: ShortcutsPage(store: store)
        case .music: MusicPage(store: store, music: dashboard.music)
        case .pets: PetsPage(store: store, dashboard: dashboard)
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
                     subtitle: "Seret untuk mengubah urutan (atas = kiri), atau pakai \"Atur tata letak\" di bawah preview untuk menyusun dan mengubah lebar langsung di Touch Bar.") {
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

// MARK: Pintasan

private struct ShortcutsPage: View {
    @ObservedObject var store: SettingsStore
    @State private var userShortcuts: [String] = []
    @State private var loadingShortcuts = true

    private var pinnedCount: Int { store.shortcuts.filter { $0.pinned && $0.enabled }.count }

    var body: some View {
        PageScaffold(title: "Pintasan",
                     subtitle: "Semua tombol Touch Bar bawaan Mac plus tambahan. Pin (📌) = tampil di widget Pintasan cepat; sisanya ada di panel ⋯. Seret untuk mengubah urutan.") {
            HStack(spacing: 10) {
                Button {
                    addApps()
                } label: {
                    Label("Tambah aplikasi…", systemImage: "plus.app")
                }
                Menu {
                    if loadingShortcuts {
                        Text("Memuat Shortcuts…")
                    } else if userShortcuts.isEmpty {
                        Text("Belum ada Shortcut di app Shortcuts")
                    } else {
                        ForEach(userShortcuts, id: \.self) { name in
                            Button(name) { store.addShortcut(.shortcut(name: name)) }
                                .disabled(store.shortcuts.contains { $0.id == ShortcutAction.shortcut(name: name).id })
                        }
                    }
                } label: {
                    Label("Tambah Shortcut", systemImage: "wand.and.stars")
                }
                .fixedSize()
                Spacer()
                Text("\(pinnedCount)/\(ShortcutEntry.maxPinned) di-pin")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            List {
                ForEach($store.shortcuts) { $entry in
                    ShortcutRow(entry: $entry,
                                canPin: pinnedCount < ShortcutEntry.maxPinned,
                                onDelete: entry.action.builtin == nil ? { remove(entry.id) } : nil)
                }
                .onMove { store.shortcuts.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
        }
        .onAppear(perform: loadShortcuts)
    }

    private func loadShortcuts() {
        DispatchQueue.global(qos: .userInitiated).async {
            let list = SystemShortcuts.listShortcuts()
            DispatchQueue.main.async {
                userShortcuts = list
                loadingShortcuts = false
            }
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Pilih aplikasi untuk Touch Bar"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addShortcut(.app(path: url.path)) }
    }

    private func remove(_ id: String) {
        store.shortcuts.removeAll { $0.id == id }
    }
}

private struct ShortcutRow: View {
    @Binding var entry: ShortcutEntry
    let canPin: Bool
    let onDelete: (() -> Void)?

    private var available: Bool { entry.action.isAvailable }

    private var caption: String {
        guard available else {
            if let b = entry.action.builtin { return b.unavailableReason }
            return "Tidak ditemukan"
        }
        var parts = [entry.action.subtitle]
        if let b = entry.action.builtin {
            if b.slider != nil { parts.append("slider") }
            if b.isToggle { parts.append("nyala/mati") }
            if b.needsAccessibility { parts.append("butuh Aksesibilitas") }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            ShortcutIcon(action: entry.action)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action.title).fontWeight(.medium)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(entry.enabled && available ? 1 : 0.5)
            Spacer()
            if let onDelete {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Hapus dari Bilah")
            }
            Button {
                entry.pinned.toggle()
            } label: {
                Image(systemName: entry.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(entry.pinned ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!available || (!entry.pinned && !canPin))
            .help(entry.pinned ? "Lepas dari Pintasan cepat" : "Pin ke Pintasan cepat")
            Toggle("", isOn: $entry.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!available)
        }
        .padding(.vertical, 3)
    }
}

private struct ShortcutIcon: View {
    let action: ShortcutAction

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35))
            switch action {
            case .app(let path):
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 22, height: 22)
            case .shortcut:
                Image(systemName: "wand.and.stars").foregroundStyle(.purple)
            case .builtin(let b):
                Image(systemName: b.symbol)
                    .foregroundStyle(Color(nsColor: b.tint == Theme.text ? .white : b.tint))
            }
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: Musik

private struct MusicPage: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var music: MusicMonitor

    private var choices: [String] {
        var extra = store.musicExtraApps + music.seenApps
        if !extra.contains(store.musicApp) { extra.append(store.musicApp) }
        return MusicApps.choices(extra: extra)
    }

    var body: some View {
        PageScaffold(title: "Musik",
                     subtitle: "Widget Musik membaca lagu dari aplikasi apa pun yang muncul di Now Playing macOS: Spotify, Music, YouTube atau SoundCloud di browser, VLC, TIDAL, dan lainnya.") {
            Form {
                Section("Sumber") {
                    Picker("Tampilkan", selection: $store.musicMode) {
                        Text("Otomatis: apa pun yang sedang diputar").tag(MusicMode.auto)
                        Text("Satu aplikasi saja").tag(MusicMode.app)
                    }
                    .pickerStyle(.radioGroup)
                    HStack {
                        Picker(store.musicMode == .app ? "Aplikasi" : "Dibuka saat belum ada musik",
                               selection: $store.musicApp) {
                            ForEach(choices, id: \.self) { id in
                                Label {
                                    Text(MusicApps.name(id))
                                } icon: {
                                    if let icon = MusicApps.icon(id) { Image(nsImage: icon) }
                                }
                                .tag(id)
                            }
                        }
                        Button("Pilih aplikasi lain…", action: pickApp)
                    }
                    Text(store.musicMode == .app
                         ? "Widget hanya menampilkan lagu dari \(MusicApps.name(store.musicApp)). Kalau aplikasinya tertutup, ketuk ▶ untuk membukanya."
                         : "Kalau belum ada yang diputar, widget menampilkan \(MusicApps.name(store.musicApp)) dengan tombol ▶ untuk membukanya.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sekarang") {
                    if let info = music.info, info.hasTrack, let id = info.bundleID {
                        HStack(spacing: 10) {
                            if let icon = MusicApps.icon(id) {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.title).fontWeight(.medium)
                                Text([info.artist, info.appName ?? MusicApps.name(id)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(info.playing ? "Diputar" : "Dijeda").foregroundStyle(info.playing ? .green : .secondary)
                        }
                    } else {
                        Text("Tidak ada yang sedang diputar.").foregroundStyle(.secondary)
                    }
                    Label(music.universal ? "Mode universal aktif: semua aplikasi terbaca"
                                          : "Mode terbatas: hanya Spotify dan Music (lewat AppleScript)",
                          systemImage: music.universal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(music.universal ? .green : .orange)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Pilih aplikasi musik"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !store.musicExtraApps.contains(id) { store.musicExtraApps.append(id) }
        store.musicApp = id
    }
}

// MARK: Peliharaan

private struct PetsPage: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var dashboard: DashboardController

    var body: some View {
        PageScaffold(title: "Peliharaan",
                     subtitle: "Ketuk peliharaan di Touch Bar untuk mengelus (❤). Ketuk tempat kosong untuk memanggilnya ke sana. Kalau lama tidak disapa, dia tidur.") {
            Form {
                Section {
                    ForEach($store.pets) { $pet in
                        PetRow(pet: $pet, canRemove: store.pets.count > 1) {
                            store.pets.removeAll { $0.id == pet.id }
                        }
                    }
                    if store.pets.count < PetConfig.maxCount {
                        Button {
                            let species: PetSpecies = store.pets.filter { $0.species == .dog }.count
                                <= store.pets.filter { $0.species == .cat }.count ? .dog : .cat
                            store.pets.append(PetConfig(species: species, variant: store.pets.count % 4,
                                                        name: species.defaultName))
                        } label: {
                            Label("Tambah peliharaan", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Peliharaan kamu")
                } footer: {
                    Text("Maksimal \(PetConfig.maxCount). Atur lebar area mainnya lewat Atur tata letak di bawah preview.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Tampilan", selection: $store.petCompact) {
                        Text("Area main lebar").tag(false)
                        Text("Kotak kecil").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Ukuran")
                } footer: {
                    Text(store.petCompact
                         ? "Kotak kecil: ±40 pt per peliharaan. Mereka duduk, tidur, dan joget di tempat tanpa jalan-jalan."
                         : "Area main lebar: peliharaan jalan-jalan dan bisa dipanggil dengan mengetuk tempat kosong.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kejar Camilan").fontWeight(.medium)
                            Text("\(store.pets.first?.name ?? "Peliharaanmu") lari di Touch Bar: ketuk untuk lompat, ketuk lagi di udara untuk lompat ganda. Lompati rintangan, jangan lompat saat burung lewat, kumpulkan camilan.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Rekor: \(UserDefaults.standard.integer(forKey: "gameBest"))")
                                .font(.caption).monospacedDigit()
                        }
                        Spacer()
                        Button {
                            dashboard.openGame()
                        } label: {
                            Label("Main di Touch Bar", systemImage: "gamecontroller.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!dashboard.available)
                    }
                } header: {
                    Text("Game")
                }

                Section("Kebiasaan") {
                    Toggle("Joget saat musik diputar", isOn: $store.petDance)
                    Toggle("Lebih sering tidur di malam hari (23.00–06.00)", isOn: $store.petNightSleep)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct PetRow: View {
    @Binding var pet: PetConfig
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PetPortrait(config: pet)
                .frame(width: 56, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Nama", text: $pet.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Picker("", selection: $pet.species) {
                        ForEach(PetSpecies.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
                HStack(spacing: 8) {
                    ForEach(Array(pet.species.variants.enumerated()), id: \.offset) { i, name in
                        let swatch = PetPalette.of(PetConfig(species: pet.species, variant: i, name: ""))
                        Button {
                            pet.variant = i
                        } label: {
                            Circle()
                                .fill(Color(nsColor: swatch.patch == nil ? swatch.body : swatch.body))
                                .overlay(Circle().fill(Color(nsColor: swatch.patch ?? swatch.dark)).frame(width: 8, height: 8)
                                    .offset(x: 4, y: -3))
                                .overlay(Circle().stroke(pet.variant == i ? Color.accentColor : Color.secondary.opacity(0.4),
                                                         lineWidth: pet.variant == i ? 2.5 : 1))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                    Text(pet.species.variants[min(pet.variant, 3)]).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canRemove {
                Button(action: onRemove) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Hapus peliharaan")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Gambar diam peliharaan (pose duduk) untuk daftar di pengaturan.
private struct PetPortrait: NSViewRepresentable {
    let config: PetConfig

    final class Portrait: NSView {
        var config: PetConfig? { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let config else { return }
            Draw.roundedRect(bounds, radius: 8, fill: NSColor.black.withAlphaComponent(0.55))
            PetRenderer.draw(config.species, PetPalette.of(config), pose: PetPose(kind: .sit, tail: 0.2),
                             at: NSPoint(x: bounds.midX - 2, y: bounds.maxY - 4), facing: 1, scale: 1.2)
        }
    }

    func makeNSView(context: Context) -> Portrait { Portrait() }
    func updateNSView(_ v: Portrait, context: Context) { v.config = config }
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
                                  detail: "Untuk tombol media, Spotlight, emoji, Notification Center, dan Control Center.") {
                        if !axTrusted {
                            Button("Minta izin") {
                                SystemActions.requestAccessibility()
                                SystemActions.openAccessibilitySettings()
                            }
                        }
                    }
                    PermissionRow(ok: nil, title: "Automation (Spotify / Music)",
                                  detail: "Hanya dipakai untuk langsung memutar Spotify/Music yang tertutup, atau kalau mode universal tidak jalan.") {
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
