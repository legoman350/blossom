// Draws the README's banner and diagrams. The layouts come from LayoutEngine itself, so the
// pictures show exactly what Blossom does. Build and run from the repo root:
//   swiftc Sources/LayoutEngine.swift Tools/ReadmeImages/main.swift -o build/readme-images
//   build/readme-images docs/images
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"
let scale: CGFloat = 2  // retina

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
// The app icon's palette.
let background = (top: color(0x3A2E6E), bottom: color(0x161331))
let petals: [NSColor] = [color(0xFF8FB0), color(0xFF8A65), color(0xD96BC8), color(0xFF6F98), color(0xF5A8E0),
                         color(0xFFB38A), color(0xE58FD6), color(0xFFA3BF)]

/// Draws into a bitmap of `size` points at 2x, flipped so y grows downward like the
/// Accessibility coordinates LayoutEngine works in.
func render(_ name: String, _ size: NSSize, _ draw: (CGRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.translateBy(x: 0, y: size.height)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png")
}

func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color textColor: NSColor = .white, centeredIn width: CGFloat? = nil) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: textColor]
    let str = NSAttributedString(string: string, attributes: attrs)
    var p = point
    if let width { p.x += (width - str.size().width) / 2 }
    str.draw(at: p)
}

/// A mini screen: dark rounded body with a menu bar strip. Returns the usable area.
func screen(_ rect: CGRect) -> CGRect {
    let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSGradient(colors: [background.top, background.bottom])!.draw(in: body, angle: 90)
    color(0xFFFFFF, 0.10).setFill()
    let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 9)
    NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
    NSBezierPath(rect: CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: 5)).fill()
    return CGRect(x: rect.minX, y: rect.minY + 9, width: rect.width, height: rect.height - 9)
}

/// Diagrams lay windows out on a real-sized screen (what LayoutEngine expects; its
/// minimum-size rules are in real points) and scale the result into the mini screen.
let realScreen = CGRect(x: 0, y: 0, width: 1440, height: 875)
func scaled(_ r: CGRect, into usable: CGRect) -> CGRect {
    let sx = usable.width / realScreen.width, sy = usable.height / realScreen.height
    return CGRect(x: usable.minX + (r.minX - realScreen.minX) * sx, y: usable.minY + (r.minY - realScreen.minY) * sy,
                  width: r.width * sx, height: r.height * sy)
}

/// A window: colored rounded rect with a lighter title bar and three dots.
func window(_ r: CGRect, _ fill: NSColor) {
    let path = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
    NSGradient(colors: [fill.blended(withFraction: 0.25, of: .white)!, fill])!.draw(in: path, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    color(0xFFFFFF, 0.28).setFill()
    NSBezierPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: min(9, r.height / 4))).fill()
    NSGraphicsContext.restoreGraphicsState()
    for i in 0..<3 where r.width > 30 {
        color(0xFFFFFF, 0.75).setFill()
        NSBezierPath(ovalIn: CGRect(x: r.minX + 5 + CGFloat(i) * 6, y: r.minY + 2.5, width: 4, height: 4)).fill()
    }
}

// MARK: Banner

render("banner", NSSize(width: 960, height: 300)) { bounds in
    NSGradient(colors: [background.top, background.bottom])!.draw(in: NSBezierPath(rect: bounds), angle: 90)
    // Faint tiled windows across the right side, laid out by the real grid engine.
    let area = CGRect(x: 650, y: 30, width: 290, height: 240)
    for (i, frame) in LayoutEngine.frames(count: 5, in: realScreen, gap: 16).enumerated() {
        window(scaled(frame, into: area), petals[i].withAlphaComponent(0.55))
    }
    if let icon = NSImage(contentsOfFile: "Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png") {
        icon.draw(in: CGRect(x: 40, y: 50, width: 200, height: 200), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: true, hints: nil)
    }
    text("Blossom", at: CGPoint(x: 260, y: 88), size: 58, weight: .bold)
    text("Tile, snap and tuck your Mac's windows", at: CGPoint(x: 263, y: 164), size: 21, color: color(0xFFFFFF, 0.85))
    text("from the menu bar", at: CGPoint(x: 263, y: 192), size: 21, color: color(0xFFFFFF, 0.85))
}

// MARK: Layouts

render("layouts", NSSize(width: 960, height: 280)) { bounds in
    color(0xFFFFFF, 0).setFill()
    let styles: [(LayoutStyle, Int, String, String)] = [
        (.grid, 5, "Grid", "Near-square grid that fits minimum sizes"),
        (.masterStack, 4, "Master + Stack", "Your window gets 60%, the rest stack"),
        (.columns, 3, "Columns", "Everything side by side"),
    ]
    let w: CGFloat = 290, h: CGFloat = 190, spacing: CGFloat = 25
    for (i, (style, count, title, caption)) in styles.enumerated() {
        let rect = CGRect(x: 15 + CGFloat(i) * (w + spacing), y: 10, width: w, height: h)
        let usable = screen(rect)
        for (j, frame) in LayoutEngine.frames(count: count, in: realScreen, style: style, gap: 24).enumerated() {
            window(scaled(frame, into: usable), petals[j])
        }
        text(title, at: CGPoint(x: rect.minX, y: rect.maxY + 14), size: 18, weight: .semibold, color: color(0x2B2350), centeredIn: w)
        text(caption, at: CGPoint(x: rect.minX, y: rect.maxY + 40), size: 13, color: color(0x6B6585), centeredIn: w)
    }
}

// MARK: Snap positions

render("snapping", NSSize(width: 960, height: 400)) { bounds in
    let positions: [(SnapPosition, String)] = [
        (.leftHalf, "⌃⌥←"), (.rightHalf, "⌃⌥→"), (.topLeft, "⌃⌥U"), (.bottomRight, "⌃⌥K"), (.maximize, "⌃⌥↩"),
        (.firstThird, "⌃⌥D"), (.centerThird, "⌃⌥D again"), (.lastTwoThirds, "⌃⌥E ×2"), (.center, "⌃⌥C"), (.topRight, "⌃⌥I"),
    ]
    let cols = 5, w: CGFloat = 170, h: CGFloat = 110, spacingX: CGFloat = 17.5, rowH: CGFloat = 190
    for (i, (position, keys)) in positions.enumerated() {
        let rect = CGRect(x: 15 + CGFloat(i % cols) * (w + spacingX), y: 10 + CGFloat(i / cols) * rowH, width: w, height: h)
        let usable = screen(rect)
        let before = realScreen.insetBy(dx: 360, dy: 200)  // the window's size before snapping (for Center)
        let frame = LayoutEngine.snapFrame(position, in: realScreen, gap: 24, window: before)
        window(scaled(frame, into: usable), petals[i % petals.count])
        text(position.title, at: CGPoint(x: rect.minX, y: rect.maxY + 10), size: 15, weight: .semibold, color: color(0x2B2350), centeredIn: w)
        text(keys, at: CGPoint(x: rect.minX, y: rect.maxY + 32), size: 13, color: color(0x6B6585), centeredIn: w)
    }
}
