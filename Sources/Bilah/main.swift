import AppKit

let arguments = CommandLine.arguments
if arguments.count > 1 {
    switch arguments[1] {
    case "hook":
        ClaudeHook.run()
        exit(0)
    case "hook-config":
        print(HookConfig.json(executable: Bundle.main.executablePath ?? arguments[0]))
        exit(0)
    case "music-status":
        // Diagnosis: apa yang terbaca sebagai Now Playing, dan lewat jalur mana.
        let monitor = MusicMonitor()
        monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        let i = monitor.info
        print("jalur:", monitor.universal ? "universal (MediaRemote)" : "cadangan (AppleScript)")
        print("app:", i?.bundleID ?? "-", "| judul:", i?.title ?? "-", "| diputar:", i?.playing ?? false,
              "| posisi:", Int(i?.currentPosition ?? 0), "/", Int(i?.duration ?? 0))
        monitor.stop()
        exit(0)
    case "snapshot-window":
        let pageArg = arguments.count > 3 ? arguments[3] : "widgets"
        Snapshot.window(path: arguments.count > 2 ? arguments[2] : "bilah-window.png",
                        page: Page(rawValue: pageArg) ?? .layout, editing: pageArg == "edit")
        exit(0)
    case "snapshot":
        Snapshot.run(path: arguments.count > 2 ? arguments[2] : "bilah-preview.png")
        exit(0)
    default:
        break
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
