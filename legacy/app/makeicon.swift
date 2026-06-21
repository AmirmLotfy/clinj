// makeicon.swift — render Clinj's 1024×1024 app icon to PNG.
// Usage: swift makeicon.swift /path/to/icon_1024.png
import Cocoa

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

// rounded-rect background with a teal→blue gradient
let rect = NSRect(x: 0, y: 0, width: S, height: S).insetBy(dx: 76, dy: 76)
let path = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
let grad = NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.74, blue: 0.69, alpha: 1.0),
                      ending:   NSColor(calibratedRed: 0.17, green: 0.45, blue: 0.88, alpha: 1.0))
grad?.draw(in: path, angle: -90)

// centered soap/sparkle glyph
let glyph = "🧼" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 560)]
let gsz = glyph.size(withAttributes: attrs)
glyph.draw(at: NSPoint(x: (S - gsz.width) / 2, y: (S - gsz.height) / 2 - 24), withAttributes: attrs)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { exit(1) }
