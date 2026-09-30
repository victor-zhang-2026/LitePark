import AppKit

/// LitePark's approved paired-card artwork, drawn in a shared 550-unit canvas.
/// Paths use the reference's top-left coordinates, then map once into AppKit.
enum BrandArtwork {
    static let primary = NSColor(srgbRed: 197 / 255, green: 138 / 255, blue: 87 / 255, alpha: 1)
    static let ink = NSColor(srgbRed: 1, green: 249 / 255, blue: 241 / 255, alpha: 1)
    static let face = NSColor(srgbRed: 105 / 255, green: 69 / 255, blue: 47 / 255, alpha: 1)

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func canvas(_ bounds: NSRect, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: bounds.width / 550, y: -bounds.height / 550)
        draw()
    }
    private static func fill(_ path: NSBezierPath, top: UInt32, bottom: UInt32) {
        NSGradient(starting: rgb(top), ending: rgb(bottom))!.draw(in: path, angle: 90)
    }
    private static func path(_ start: NSPoint, _ body: (NSBezierPath) -> Void) -> NSBezierPath {
        let result = NSBezierPath()
        result.move(to: start)
        body(result)
        result.close()
        return result
    }
    private static func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

    static func drawAppMark(in bounds: NSRect) {
        canvas(bounds) {
            // The rear card ends at the gap; no overlap or masking approximation.
            let back = path(p(354, 184)) { s in
                s.line(to: p(223, 214))
                s.curve(to: p(134, 309), controlPoint1: p(156, 226), controlPoint2: p(124, 259))
                s.line(to: p(144, 377))
                s.curve(to: p(89, 342), controlPoint1: p(111, 383), controlPoint2: p(95, 369))
                s.line(to: p(71, 235))
                s.curve(to: p(111, 164), controlPoint1: p(63, 201), controlPoint2: p(78, 174))
                s.line(to: p(280, 119))
                s.curve(to: p(349, 153), controlPoint1: p(317, 106), controlPoint2: p(340, 118))
            }
            fill(back, top: 0xFFD69D, bottom: 0xFFAD58)
            let front = path(p(204, 229)) { s in
                s.line(to: p(362, 201))
                s.curve(to: p(443, 250), controlPoint1: p(405, 192), controlPoint2: p(438, 208))
                s.line(to: p(460, 343))
                s.curve(to: p(415, 408), controlPoint1: p(468, 382), controlPoint2: p(449, 401))
                s.line(to: p(236, 442))
                s.curve(to: p(166, 402), controlPoint1: p(201, 449), controlPoint2: p(173, 434))
                s.line(to: p(152, 304))
                s.curve(to: p(204, 229), controlPoint1: p(144, 264), controlPoint2: p(163, 239))
            }
            fill(front, top: 0xFFBE50, bottom: 0xFF6505)
            for (x, y) in [(CGFloat(313), CGFloat(320)), (375, 309)] {
                let eye = NSBezierPath(roundedRect: NSRect(x: x - 17, y: y - 23, width: 34, height: 46), xRadius: 17, yRadius: 17)
                var rotation = AffineTransform()
                rotation.translate(x: x, y: y)
                rotation.rotate(byDegrees: -8)
                rotation.translate(x: -x, y: -y)
                eye.transform(using: rotation)
                fill(eye, top: 0xA5430B, bottom: 0x672503)
            }
        }
    }

    static func drawTrigger(in circle: NSRect, hover: CGFloat) {
        canvas(circle) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            // Ring is drawn by the caller and never scales. Disc and mark move together.
            let amount = 1 + 0.06 * hover
            context.translateBy(x: 275, y: 275)
            context.scaleBy(x: amount, y: amount)
            context.translateBy(x: -275, y: -275)
            let disc = NSBezierPath(ovalIn: NSRect(x: 40, y: 40, width: 470, height: 470))
            let top = rgb(0xFFA629).blended(withFraction: 0.12 * hover, of: rgb(0xC35C16))!
            let bottom = rgb(0xFF6105).blended(withFraction: 0.12 * hover, of: rgb(0xC35C16))!
            NSGradient(starting: top, ending: bottom)!.draw(in: disc, angle: 70)
            let back = path(p(335, 222)) { s in
                s.line(to: p(237, 222))
                s.curve(to: p(162, 294), controlPoint1: p(191, 219), controlPoint2: p(162, 248))
                s.line(to: p(162, 352))
                s.curve(to: p(122, 316), controlPoint1: p(138, 354), controlPoint2: p(126, 339))
                s.line(to: p(107, 250))
                s.curve(to: p(128, 186), controlPoint1: p(100, 219), controlPoint2: p(109, 198))
                s.curve(to: p(214, 162), controlPoint1: p(149, 175), controlPoint2: p(181, 170))
                s.line(to: p(274, 149))
                s.curve(to: p(330, 190), controlPoint1: p(309, 143), controlPoint2: p(326, 161))
            }
            fill(back, top: 0xFFFFFF, bottom: 0xFFF4E6)
            let front = NSBezierPath(roundedRect: NSRect(x: 178, y: 236, width: 246, height: 175), xRadius: 47, yRadius: 47)
            fill(front, top: 0xFFFFFF, bottom: 0xFFFAF4)
            for x: CGFloat in [266, 328] {
                let eye = NSBezierPath(roundedRect: NSRect(x: x, y: 297, width: 34, height: 44), xRadius: 17, yRadius: 17)
                fill(eye, top: 0xFF961B, bottom: 0xFF7307)
            }
        }
    }
}
