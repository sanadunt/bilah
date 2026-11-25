// Gambar ikon app Bilah lalu bungkus jadi .icns.
// Pakai: swift scripts/make-icon.swift build/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Badan ikon (grid macOS: 824 pt di kanvas 1024).
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.23, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 1))!.draw(in: body, angle: -90)

    // Bilah hitam seperti Touch Bar.
    let bar = NSRect(x: 168, y: 446, width: 688, height: 132)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 30, yRadius: 30).fill()

    // Empat kapsul widget yang menyala.
    let colors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.77, blue: 0.26, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.52, blue: 0.38, alpha: 1),
        NSColor(srgbRed: 0.30, green: 0.85, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 0.38, green: 0.82, blue: 0.93, alpha: 1),
    ]
    let widths: [CGFloat] = [190, 150, 130, 110]
    var x: CGFloat = bar.minX + 26
    for (i, w) in widths.enumerated() {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = colors[i].withAlphaComponent(0.8)
        glow.shadowBlurRadius = 26
        glow.set()
        colors[i].setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: bar.midY - 26, width: w, height: 52), xRadius: 26, yRadius: 26).fill()
        NSGraphicsContext.restoreGraphicsState()
        x += w + 24
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Bilah-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", output]
try! p.run()
p.waitUntilExit()
try? fm.removeItem(at: iconset)
exit(p.terminationStatus)
