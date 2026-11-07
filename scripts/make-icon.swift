import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
        NSColor(calibratedRed: 0.055, green: 0.20, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedRed: 0.58, green: 0.87, blue: 0.72, alpha: 0.28).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 226, y: 226, width: 572, height: 572))
        ring.lineWidth = 7
        ring.stroke()
        if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .light)
                .applying(.init(paletteColors: [NSColor(calibratedRed: 0.66, green: 0.94, blue: 0.79, alpha: 1)]))
            leaf.withSymbolConfiguration(config)?.draw(in: NSRect(x: 325, y: 325, width: 374, height: 374))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
