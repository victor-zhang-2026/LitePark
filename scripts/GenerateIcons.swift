import AppKit

/// Compile with BrandArtwork.swift to regenerate every icon size from the same
/// vector artwork used by the floating trigger. No separate logo approximation.
@main
struct GenerateIcons {
    static func main() throws {
        let output = URL(fileURLWithPath: "Resources/LitePark.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
            ("icon_1024x1024", 1024)
        ]
        for (name, pixels) in sizes {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            BrandArtwork.ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 1000, height: 1000),
                         xRadius: 230, yRadius: 230).fill()
            BrandArtwork.drawAppMark(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "IconGeneration", code: 1)
            }
            try png.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        }
    }
}
