// makeicon.swift — render Clinj's app icon (custom-drawn, no emoji).
// A gradient squircle with a sweeping arc and a sparkle cluster.
// Usage: swift makeicon.swift /path/to/icon_1024.png
import Cocoa

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// ── squircle background ───────────────────────────────────────────────────────
let inset: CGFloat = 84
let rect = NSRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)

// soft drop shadow
ctx.saveGState()
let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.28)
sh.shadowOffset = NSSize(width: 0, height: -18); sh.shadowBlurRadius = 40; sh.set()
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()

squircle.addClip()
// diagonal gradient: deep indigo → blue → cyan
let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.31, blue: 0.93, alpha: 1),   // indigo
    NSColor(srgbRed: 0.19, green: 0.51, blue: 0.95, alpha: 1),   // blue
    NSColor(srgbRed: 0.13, green: 0.78, blue: 0.85, alpha: 1),   // cyan
], atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB)!
grad.draw(in: rect, angle: -55)

// soft top sheen (subtle, no hard edge)
let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0.0)])!
sheen.draw(in: rect, angle: -90)

// ── sweeping motion trail (the "clean sweep"), lower-left → up-right ───────────
let arc = NSBezierPath()
arc.move(to: NSPoint(x: 285, y: 415))
arc.curve(to: NSPoint(x: 560, y: 560),
          controlPoint1: NSPoint(x: 360, y: 360), controlPoint2: NSPoint(x: 470, y: 470))
arc.lineWidth = 40; arc.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.26).setStroke(); arc.stroke()

// ── sparkle cluster ───────────────────────────────────────────────────────────
func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ R: CGFloat) -> NSBezierPath {
    let r = R * 0.30
    let p = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [
        (0, R), (r, r), (R, 0), (r, -r),
        (0, -R), (-r, -r), (-R, 0), (-r, r),
    ]
    for (i, pt) in pts.enumerated() {
        let q = NSPoint(x: cx + pt.0, y: cy + pt.1)
        if i == 0 { p.move(to: q) } else { p.line(to: q) }
    }
    p.close()
    return p
}
func drawSparkle(_ cx: CGFloat, _ cy: CGFloat, _ R: CGFloat) {
    ctx.saveGState()
    let g = NSShadow(); g.shadowColor = NSColor.white.withAlphaComponent(0.65)
    g.shadowOffset = .zero; g.shadowBlurRadius = 26; g.set()
    NSColor.white.setFill(); sparkle(cx, cy, R).fill()
    ctx.restoreGState()
}
drawSparkle(600, 660, 172)   // large
drawSparkle(760, 770, 70)    // medium (clustered up-right of large)
drawSparkle(690, 520, 46)    // small

img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!); exit(1)
}
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { exit(1) }
