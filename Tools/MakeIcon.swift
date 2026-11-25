// Draws Blossom's app icon: four window-shaped petals arranged like a flower, on a
// macOS-style rounded square. Run with:
//   swift Tools/MakeIcon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png
import AppKit

let canvas: CGFloat = 1024
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Body: Apple's macOS icon grid puts an 824pt rounded square in the 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
color(0x1E1B3A).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(0x3A2E6E), color(0x161331)])!.draw(in: bodyPath, angle: -90)

// Petals: four rounded "windows" in a 2×2 tile, turned 45° so the grid reads as a flower.
ctx.saveGState()
ctx.translateBy(x: canvas / 2, y: canvas / 2)
ctx.rotate(by: .pi / 4)
let petal: CGFloat = 250, gap: CGFloat = 26
let petalColors: [(UInt32, UInt32)] = [(0xFFB3C9, 0xFF6F98), (0xFFC7A8, 0xFF8A65), (0xF5A8E0, 0xD96BC8), (0xFFD3DE, 0xFF8FB0)]
for (i, (dx, dy)) in [(-1, 1), (1, 1), (1, -1), (-1, -1)].enumerated() {
    let origin = CGPoint(x: dx < 0 ? -gap / 2 - petal : gap / 2, y: dy < 0 ? -gap / 2 - petal : gap / 2)
    let rect = NSRect(origin: origin, size: NSSize(width: petal, height: petal))
    // The corner nearest the center stays tight, the outer corner rounds fully: a petal shape.
    let path = NSBezierPath(roundedRect: rect, xRadius: 70, yRadius: 70)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0xFF6F98, 0.45)
    glow.shadowBlurRadius = 40
    glow.set()
    color(petalColors[i].1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Light at the flower's heart, deeper toward the petal tip, the same for every petal.
    let outward = atan2(Double(dy), Double(dx)) * 180 / .pi
    NSGradient(colors: [color(petalColors[i].0), color(petalColors[i].1)])!.draw(in: path, angle: outward)

    // A window "title bar" stripe on one outer edge, so each petal reads as a window.
    // Petal by petal the edge turns a quarter, a pinwheel with four-way symmetry.
    let inset: CGFloat = 46, thick: CGFloat = 26, margin: CGFloat = 38
    let bar: NSRect
    switch (dx, dy) {
    case (-1, 1):  bar = NSRect(x: rect.minX + inset, y: rect.maxY - margin - thick, width: petal - 2 * inset, height: thick) // top edge
    case (1, 1):   bar = NSRect(x: rect.maxX - margin - thick, y: rect.minY + inset, width: thick, height: petal - 2 * inset) // right edge
    case (1, -1):  bar = NSRect(x: rect.minX + inset, y: rect.minY + margin, width: petal - 2 * inset, height: thick)         // bottom edge
    default:       bar = NSRect(x: rect.minX + margin, y: rect.minY + inset, width: thick, height: petal - 2 * inset)         // left edge
    }
    color(0xFFFFFF, 0.55).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 13, yRadius: 13).fill()
}
ctx.restoreGState()

// Center: the flower's heart.
let heart = NSRect(x: canvas / 2 - 62, y: canvas / 2 - 62, width: 124, height: 124)
NSGraphicsContext.saveGraphicsState()
let heartShadow = NSShadow()
heartShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
heartShadow.shadowBlurRadius = 18
heartShadow.set()
color(0xFFD166).setFill()
NSBezierPath(ovalIn: heart).fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(0xFFE59A), color(0xFFB830)])!.draw(in: NSBezierPath(ovalIn: heart), angle: -90)

NSGraphicsContext.current = nil
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
