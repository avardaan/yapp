import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "design/icons")
for name in ["01-charcoal", "02-amber", "03-yappman"] {
    guard let image = NSImage(contentsOf: root.appendingPathComponent(name + ".svg")) else { fatalError("SVG decode failed") }
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap failed") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + ".png"))
}
print("Rendered three 1024px transparent PNG masters from the SVGs.")
