import AppKit

/// The menu bar icon: the app icon's blossom (four window petals turned 45° around a
/// golden heart), in the app icon's colors. Being colored, it's not a template image, so
/// macOS won't recolor it for the menu bar. The mid-tone petals read on both light and dark bars.
enum MenuBarIcon {
    /// Same petal positions and colors as Tools/MakeIcon.swift: (near the heart, at the tip).
    /// Positions are before the 45° turn, which moves (1, 1) to the top.
    private static let petals: [(dx: CGFloat, dy: CGFloat, inner: UInt32, outer: UInt32)] = [
        (-1, 1, 0xFFB3C9, 0xFF6F98),  // left: pink
        (1, 1, 0xFFC7A8, 0xFF8A65),   // top: peach → coral
        (1, -1, 0xF5A8E0, 0xD96BC8),  // right: orchid
        (-1, -1, 0xFFD3DE, 0xFF8FB0), // bottom: light pink
    ]

    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = bounds.width / 18  // designed on an 18pt grid

            ctx.saveGState()
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.rotate(by: .pi / 4)
            let petal = 5.6 * s, gap = 1.3 * s
            for p in petals {
                let origin = CGPoint(x: p.dx < 0 ? -gap / 2 - petal : gap / 2, y: p.dy < 0 ? -gap / 2 - petal : gap / 2)
                let path = NSBezierPath(roundedRect: NSRect(origin: origin, size: NSSize(width: petal, height: petal)),
                                        xRadius: 1.7 * s, yRadius: 1.7 * s)
                // Lighter at the heart, deeper at the tip, like the app icon. The light end
                // starts halfway to the deep color: at 18pt the palest tints wash out on a
                // light menu bar.
                let outward = atan2(Double(p.dy), Double(p.dx)) * 180 / .pi
                let light = color(p.inner).blended(withFraction: 0.5, of: color(p.outer)) ?? color(p.inner)
                NSGradient(colors: [light, color(p.outer)])?.draw(in: path, angle: outward)
            }
            ctx.restoreGState()

            // A small golden heart with a thin clear ring around it, so it stays distinct
            // from the petals at 18pt.
            let ring = NSRect(x: bounds.midX - 2.4 * s, y: bounds.midY - 2.4 * s, width: 4.8 * s, height: 4.8 * s)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: ring).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let heart = NSBezierPath(ovalIn: ring.insetBy(dx: 0.9 * s, dy: 0.9 * s))
            NSGradient(colors: [color(0xFFE59A), color(0xFFB830)])?.draw(in: heart, angle: -90)
            return true
        }
        image.isTemplate = false  // keep the colors
        image.accessibilityDescription = "Blossom"
        return image
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
