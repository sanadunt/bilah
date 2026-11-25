import AppKit
import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case layout, shortcuts, music, dock, pets, info, focus, claude, appearance, permissions, updates, about

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case touchBar = "Touch Bar", widgets = "Widget", app = "Aplikasi"
    }

    var group: Group {
        switch self {
        case .layout, .shortcuts: .touchBar
        case .music, .dock, .pets, .info, .focus, .claude: .widgets
        case .appearance, .permissions, .updates, .about: .app
        }
    }

    var title: String {
        switch self {
        case .layout: "Tata letak"
        case .shortcuts: "Pintasan"
        case .music: "Musik"
        case .dock: "Dock"
        case .pets: "Peliharaan & Game"
        case .info: "Info & Lokasi"
        case .focus: "Fokus"
        case .claude: "Claude Code"
        case .appearance: "Tampilan"
        case .permissions: "Izin"
        case .updates: "Update"
        case .about: "Tentang"
        }
    }

    var symbol: String {
        switch self {
        case .layout: "rectangle.3.group.fill"
        case .shortcuts: "square.grid.2x2.fill"
        case .music: "music.note"
        case .dock: "dock.rectangle"
        case .pets: "pawprint.fill"
        case .info: "location.fill"
        case .focus: "timer"
        case .claude: "sparkle"
        case .appearance: "paintbrush.fill"
        case .permissions: "lock.fill"
        case .updates: "arrow.down.circle.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .layout: .blue
        case .shortcuts: .indigo
        case .music: .pink
        case .dock: .cyan
        case .pets: .orange
        case .info: .green
        case .focus: .red
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .appearance: .purple
        case .permissions: .gray
        case .updates: .teal
        case .about: .gray
        }
    }
}

final class Navigation: ObservableObject {
    @Published var page: Page = .layout
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
            let w = Self.makeWindow(root)
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("BilahWindow")
            window = w
        }
        // Selama jendela terbuka Bilah tampil di Dock dan ⌘-Tab; ditutup = kembali jadi app menu bar.
        NSApp.setActivationPolicy(.regular)
        dashboard.previewActive = true
        dashboard.refreshNow()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Jendela utama (dipakai app dan alat uji `layout-check`, supaya yang diuji persis sama).
    static func makeWindow(_ root: MainView) -> NSWindow {
        let host = NSHostingController(rootView: root)
        // Judul & toolbar SwiftUI diteruskan ke jendela AppKit (gaya System Settings).
        host.sceneBridgingOptions = [.title, .toolbars]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.toolbarStyle = .unified
        w.title = "Bilah"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 860, height: 560)
        w.setContentSize(NSSize(width: 1080, height: 740))
        return w
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
        NavigationSplitView {
            List(selection: Binding(get: { navigation.page }, set: { if let p = $0 { navigation.page = p } })) {
                ForEach(Page.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Page.allCases.filter { $0.group == group }) { page in
                            SidebarLabel(page: page)
                                .badge(page == .updates && updater.updateAvailable ? Text("Baru") : nil)
                                .tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .navigationTitle(navigation.page.title)
                .toolbar { toolbar }
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder private var detail: some View {
        switch navigation.page {
        case .layout: LayoutPage(store: store, dashboard: dashboard, editor: editor)
        case .shortcuts: ShortcutsPage(store: store)
        case .music: MusicPage(store: store, music: dashboard.music)
        case .dock: DockPage(store: store)
        case .pets: PetsPage(store: store, dashboard: dashboard)
        case .info: InfoPage(store: store, clipboard: dashboard.clipboard)
        case .focus: FocusPage(store: store)
        case .claude: ClaudePage()
        case .appearance: AppearancePage(store: store)
        case .permissions: PermissionsPage(dashboard: dashboard)
        case .updates: UpdatesPage(updater: updater)
        case .about: AboutPage()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !dashboard.available {
                Label("Touch Bar tidak tersedia", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
            if updater.updateAvailable, let v = updater.latest?.version {
                Button {
                    navigation.page = .updates
                } label: {
                    Label("Update v\(v)", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.green)
            }
            Button {
                dashboard.toggle()
            } label: {
                Label(dashboard.isShown ? "Sembunyikan dari Touch Bar" : "Tampilkan di Touch Bar",
                      systemImage: dashboard.isShown ? "eye.slash" : "eye")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!dashboard.available)
        }
    }
}

/// Ikon berwarna di sidebar, seperti System Settings.
private struct SidebarLabel: View {
    let page: Page

    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.color.gradient))
        }
    }
}

/// Isi halaman: keterangan singkat di atas, lalu isinya. Judul halaman tampil di toolbar.
private struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Jangan pakai .fixedSize(vertical:) di sini: di dalam NavigationSplitView itu membuat seluruh halaman
            // memakai tinggi idealnya (bisa 1.900 pt), sehingga isi dan sidebar terdorong keluar jendela.
            // layoutPriority cukup supaya keterangan tetap utuh dan Form/List di bawahnya yang menggulung.
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
                .padding(.horizontal, 28)
                .padding(.top, 14)
            content
        }
    }
}

// MARK: Tata letak

private struct LayoutPage: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var dashboard: DashboardController
    @ObservedObject var editor: LayoutEditorState

    var body: some View {
        VStack(spacing: 0) {
            // Panel preview tetap di atas: tetap terlihat saat widget di bawahnya dinyalakan/dimatikan.
            VStack(spacing: 12) {
                BarPreview(settings: store, editor: editor, dashboard: dashboard)
                    .frame(maxWidth: .infinity)
                LayoutToolbar(store: store, editor: editor)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Form {
            Section {
                PageBar(store: store)
                ForEach(Array(store.order.enumerated()), id: \.element) { index, kind in
                    WidgetRow(kind: kind,
                              enabled: Binding(get: { store.isEnabled(kind) }, set: { store.setEnabled(kind, $0) }),
                              canMoveUp: index > 0, canMoveDown: index < store.order.count - 1) { store.move(kind, by: $0) }
                }
            } header: {
                Text("Widget di halaman \"\(store.pages[min(store.currentPage, store.pages.count - 1)].name)\"")
            } footer: {
                Text("Urutan atas ke bawah = kiri ke kanan di Touch Bar.").foregroundStyle(.secondary)
            }

            PagesSections(store: store)
            }
            .formStyle(.grouped)
        }
    }
}

private struct WidgetRow: View {
    let kind: WidgetKind
    @Binding var enabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: kind.tint).opacity(enabled ? 0.22 : 0.08))
                Image(systemName: kind.symbol)
                    .foregroundStyle(Color(nsColor: kind.tint).opacity(enabled ? 1 : 0.4))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).fontWeight(.medium)
                Text(kind.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(enabled ? 1 : 0.55)
            Spacer()
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .help("Geser ke kiri")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .help("Geser ke kanan")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Pintasan

private struct ShortcutsPage: View {
    @ObservedObject var store: SettingsStore
    @State private var userShortcuts: [String] = []
    @State private var loadingShortcuts = true
    @State private var editingCommand: CommandDraft?

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
                Button {
                    editingCommand = CommandDraft()
                } label: {
                    Label("Tambah perintah…", systemImage: "terminal")
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
        .sheet(item: $editingCommand) { draft in
            CommandSheet(draft: draft) { saved in
                store.addShortcut(.command(name: saved.name, script: saved.script, directory: saved.directory))
                editingCommand = nil
            } onCancel: {
                editingCommand = nil
            }
        }
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
        if case .command(_, let script, let dir) = entry.action {
            parts.append(script.replacingOccurrences(of: "\n", with: "; "))
            if !dir.isEmpty { parts.append(dir) }
        }
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
            case .command:
                Image(systemName: "terminal.fill").foregroundStyle(.green)
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

// MARK: Perintah

struct CommandDraft: Identifiable {
    let id = UUID()
    var name = ""
    var script = ""
    var directory = ""
}

private struct CommandSheet: View {
    @State var draft: CommandDraft
    let onSave: (CommandDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tombol perintah").font(.title3.weight(.semibold))
            Text("Dijalankan dengan zsh (seperti di Terminal). Tombolnya menampilkan ⏳ saat berjalan, lalu ✓ atau ✗. Output dicatat di ~/Library/Logs/Bilah/perintah.log.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Nama tombol, mis. Build Bilah", text: $draft.name)
            VStack(alignment: .leading, spacing: 4) {
                Text("Perintah").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.script)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            HStack {
                TextField("Folder kerja (opsional), mis. ~/Projects/bilah", text: $draft.directory)
                Button("Pilih…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        draft.directory = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    }
                }
            }
            HStack {
                Spacer()
                Button("Batal", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Tambah") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: Dock

private struct DockPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PageScaffold(title: "Dock",
                     subtitle: "Salinan Dock di Touch Bar sebagai widget. Ketuk ikon untuk membuka aplikasinya. Lebarnya diatur lewat Atur tata letak: makin lebar, makin banyak ikon yang muat; sisanya lewat tombol +N.") {
            Form {
                Section("Urutan") {
                    Picker("Urutkan", selection: $store.dockOrder) {
                        ForEach(DockOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Section("Tampilan") {
                    Picker("Ukuran ikon", selection: $store.dockIconSize) {
                        ForEach(DockIconSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Titik di bawah aplikasi yang sedang jalan", isOn: $store.dockShowRunning)
                    Toggle("Badge notifikasi belum dibaca", isOn: $store.dockShowBadges)
                }
                Section {
                    Label(SystemActions.hasAccessibility
                          ? "Urutan dibaca langsung dari Dock (izin Aksesibilitas sudah ada)."
                          : "Tanpa izin Aksesibilitas: aplikasi yang di-pin di Dock + yang sedang jalan, tanpa badge.",
                          systemImage: SystemActions.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(SystemActions.hasAccessibility ? .green : .orange)
                } footer: {
                    Text("Widget Dock belum aktif? Nyalakan di Tata letak › Widget di halaman ini.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
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

// MARK: Halaman & Profil

/// Pemilih halaman + menu tambah/ganti nama/hapus. Dipakai di halaman Widget dan di bawah preview.
struct PageBar: View {
    @ObservedObject var store: SettingsStore
    @State private var renaming = false
    @State private var newName = ""

    private var pagePicker: some View {
        Picker("Halaman", selection: Binding(get: { store.currentPage }, set: { store.showPage($0) })) {
            ForEach(Array(store.pages.enumerated()), id: \.element.id) { i, page in Text(page.name).tag(i) }
        }
        .labelsHidden()
    }

    var body: some View {
        HStack(spacing: 10) {
            if store.pages.count > 1 {
                // Tombol tersegmen kalau muat; kalau sempit atau halamannya banyak, otomatis jadi menu tarik-turun.
                // (Segmented + fixedSize saja tumbuh ±110 pt per halaman dan bisa mendorong sidebar keluar jendela.)
                ViewThatFits(in: .horizontal) {
                    pagePicker.pickerStyle(.segmented).fixedSize()
                    pagePicker.pickerStyle(.menu).fixedSize()
                }
            }
            Menu {
                Button("Tambah halaman") { store.addPage(named: "Halaman \(store.pages.count + 1)") }
                Button("Ganti nama halaman ini…") {
                    newName = store.pages[store.currentPage].name
                    renaming = true
                }
                Button("Hapus halaman ini", role: .destructive) { store.removePage(at: store.currentPage) }
                    .disabled(store.pages.count < 2)
            } label: {
                Label(store.pages.count > 1 ? "Halaman" : "Tambah halaman", systemImage: "rectangle.stack")
            }
            .fixedSize()
        }
        .alert("Ganti nama halaman", isPresented: $renaming) {
            TextField("Nama", text: $newName)
            Button("Simpan") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.pages[store.currentPage].name = name }
            }
            Button("Batal", role: .cancel) {}
        }
    }
}

private struct PagesSections: View {
    @ObservedObject var store: SettingsStore

    private var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Group {
            Group {
                Section {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { i, page in
                        HStack {
                            Image(systemName: i == store.currentPage ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(i == store.currentPage ? Color.accentColor : .secondary)
                                .onTapGesture { store.showPage(i) }
                            TextField("Nama", text: Binding(get: { store.pages[i].name }, set: { store.pages[i].name = $0 }))
                                .textFieldStyle(.plain)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(page.order.filter { !page.disabled.contains($0) }.count) widget")
                                .foregroundStyle(.secondary)
                            Button { store.removePage(at: i) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .disabled(store.pages.count < 2)
                        }
                    }
                    Button {
                        store.addPage(named: "Halaman \(store.pages.count + 1)")
                    } label: {
                        Label("Tambah halaman", systemImage: "plus")
                    }
                } header: {
                    Text("Halaman")
                } footer: {
                    Text("Usap Touch Bar ke kiri/kanan, atau ketuk titik di sebelah ‹, untuk pindah halaman. Yang diatur di atas selalu halaman yang sedang dipilih.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Ganti halaman otomatis sesuai aplikasi yang aktif", isOn: $store.autoPageSwitch)
                    ForEach(store.appPages.keys.sorted(), id: \.self) { bundleID in
                        HStack {
                            if let icon = MusicApps.icon(bundleID) { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                            Text(MusicApps.name(bundleID))
                            Spacer()
                            Picker("", selection: Binding(get: { store.appPages[bundleID] ?? store.pages[0].id },
                                                          set: { store.appPages[bundleID] = $0 })) {
                                ForEach(store.pages) { Text($0.name).tag($0.id) }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                            Button { store.appPages[bundleID] = nil } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Menu {
                        ForEach(running, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) {
                                store.appPages[app.bundleIdentifier!] = store.pages[min(1, store.pages.count - 1)].id
                            }
                        }
                        Divider()
                        Button("Pilih aplikasi lain…", action: pickApp)
                    } label: {
                        Label("Tambah aplikasi", systemImage: "plus.app")
                    }
                    .fixedSize()
                    .disabled(store.pages.count < 2)
                } header: {
                    Text("Profil per aplikasi")
                } footer: {
                    Text(store.pages.count < 2
                         ? "Buat minimal dua halaman dulu."
                         : "Contoh: halaman \"Kerja\" dengan tombol perintah build untuk Godot atau Xcode. Saat pindah ke aplikasi tanpa profil, halaman kembali seperti semula.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        store.appPages[id] = store.pages[min(1, store.pages.count - 1)].id
    }
}

// MARK: Info & Lokasi

private struct InfoPage: View {
    @ObservedObject var store: SettingsStore
    let clipboard: ClipboardWidget
    @State private var customName = ""
    @State private var customLat = ""
    @State private var customLon = ""
    @State private var cleared = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH.mm"
        return f
    }()

    var body: some View {
        PageScaffold(title: "Info & Lokasi",
                     subtitle: "Lokasi untuk jadwal sholat dan cuaca, plus pengaturan widget info lainnya. Widget ini ada di halaman \"Info\": usap Touch Bar untuk melihatnya.") {
            Form {
                Section {
                    Picker("Kota", selection: $store.location) {
                        ForEach(CityLocation.presets, id: \.self) { Text($0.name).tag($0) }
                        if !CityLocation.presets.contains(store.location) {
                            Text(store.location.name).tag(store.location)
                        }
                    }
                    HStack {
                        TextField("Nama tempat", text: $customName)
                        TextField("Lintang (mis. -6.2)", text: $customLat).frame(width: 130)
                        TextField("Bujur (mis. 106.8)", text: $customLon).frame(width: 130)
                        Button("Pakai") {
                            if let lat = Double(customLat.replacingOccurrences(of: ",", with: ".")),
                               let lon = Double(customLon.replacingOccurrences(of: ",", with: ".")),
                               abs(lat) <= 90, abs(lon) <= 180 {
                                store.location = CityLocation(name: customName.isEmpty ? "Lokasiku" : customName,
                                                              latitude: lat, longitude: lon)
                            }
                        }
                    }
                } header: {
                    Text("Lokasi")
                } footer: {
                    Text("Kota tidak ada di daftar? Isi koordinat sendiri (bisa dilihat di Apple Maps atau Google Maps).")
                        .foregroundStyle(.secondary)
                }

                Section {
                    let times = PrayerTimes.times(for: Date(), at: store.location)
                    HStack {
                        ForEach(times, id: \.0) { prayer, time in
                            VStack(spacing: 2) {
                                Text(prayer.rawValue).font(.caption).foregroundStyle(.secondary)
                                Text(Self.time.string(from: time)).font(.body.monospacedDigit()).fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } header: {
                    Text("Jadwal sholat hari ini · \(store.location.name)")
                } footer: {
                    Text("Dihitung offline dengan parameter Kemenag RI (Subuh 20°, Isya 18°, Ashar Syafi'i, ihtiyat 2 menit). Bisa selisih 1–2 menit dari jadwal resmi daerahmu.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("\(clipboard.history.items.count) teks tersimpan (hanya di memori, hilang saat Bilah ditutup)")
                        Spacer()
                        Button(cleared ? "Dibersihkan ✓" : "Bersihkan") {
                            clipboard.history.clear()
                            clipboard.push()
                            cleared = true
                        }
                    }
                } header: {
                    Text("Riwayat clipboard")
                } footer: {
                    Text("Isi dari pengelola sandi (1Password, Bitwarden, dll.) tidak pernah dicatat. Ketuk salah satu teks di Touch Bar untuk menempelkannya lagi (butuh izin Aksesibilitas; tanpa izin, teks hanya disalin).")
                        .foregroundStyle(.secondary)
                }

                Section("Lainnya") {
                    Label("Rapat berikutnya memakai Kalender macOS; izinnya diminta saat widget pertama kali diketuk.", systemImage: "calendar")
                    Label("Badge aplikasi dibaca dari Dock dan butuh izin Aksesibilitas.", systemImage: "app.badge")
                    Label("Cuaca dari Open-Meteo, diperbarui tiap 20 menit. Hanya koordinat kota yang dikirim.", systemImage: "cloud.sun")
                }
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: Umum

private struct AppearancePage: View {
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        PageScaffold(title: "Tampilan", subtitle: "Tema widget, cara dashboard tampil di Touch Bar, dan login.") {
            Form {
                Section("Tema") {
                    Picker("Kapsul widget", selection: $store.pillStyle) {
                        ForEach(PillStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Warna aksen")
                        Spacer()
                        ForEach(AccentChoice.allCases) { choice in
                            Button {
                                store.accent = choice
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: choice.color))
                                    .overlay(Circle().stroke(store.accent == choice ? Color.primary : .clear, lineWidth: 2).padding(-3))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help(choice.title)
                        }
                    }
                }

                Section("Touch Bar") {
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

private struct FocusPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        PageScaffold(title: "Fokus",
                     subtitle: "Timer Pomodoro dan pengingat istirahat.") {
            Form {
                Section {
                    Stepper("Fokus: \(store.focusMinutes) menit", value: $store.focusMinutes, in: 5...120, step: 5)
                    Stepper("Istirahat: \(store.breakMinutes) menit", value: $store.breakMinutes, in: 1...30)
                } header: {
                    Text("Pomodoro")
                } footer: {
                    Text("Ketuk widget Pomodoro untuk mulai atau jeda. Saat dijeda, ketuk ↺ untuk reset. Fokus selesai langsung lanjut istirahat.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Ingatkan istirahat", isOn: $store.restReminder)
                    Stepper("Setelah \(store.restInterval) menit kerja tanpa jeda", value: $store.restInterval, in: 20...120, step: 5)
                        .disabled(!store.restReminder)
                } header: {
                    Text("Pengingat istirahat")
                } footer: {
                    Text("Muncul di Touch Bar dan peliharaan ikut menyapa. Kalau kamu diam 5 menit, hitungannya mulai lagi dari nol.")
                        .foregroundStyle(.secondary)
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
                    PermissionRow(ok: CalendarService.authorized ? true : (CalendarService.denied ? false : nil),
                                  title: "Kalender",
                                  detail: "Untuk widget Rapat berikutnya.") {
                        if !CalendarService.authorized {
                            Button(CalendarService.denied ? "Buka pengaturan" : "Minta izin") {
                                if CalendarService.denied {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                                } else {
                                    CalendarService().requestAccess()
                                }
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
