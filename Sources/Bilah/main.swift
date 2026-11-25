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
    case "snapshot-window":
        let page = arguments.count > 3 ? Page(rawValue: arguments[3]) ?? .widgets : .widgets
        Snapshot.window(path: arguments.count > 2 ? arguments[2] : "bilah-window.png", page: page)
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
