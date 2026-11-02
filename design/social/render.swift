import AppKit

// Rebuild with: swift design/social/render.swift
let output = URL(fileURLWithPath: "website/social-card.png")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
let transform = NSAffineTransform()
transform.translateX(by: 0, yBy: 630)
transform.scaleX(by: 1, yBy: -1)
transform.concat()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}
let paper = color(245,243,235), ink = color(34,39,32), amber = color(244,178,65)
paper.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ tint: NSColor) {
    let context = NSGraphicsContext.current!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: tint])
    NSGraphicsContext.current = context
}
func mark(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
    let path = NSBezierPath()
    let center = NSPoint(x: x+size/2, y: y+size/2)
    path.move(to: center)
    path.appendArc(withCenter: center, radius: size/2, startAngle: 25, endAngle: 335, clockwise: false)
    path.close(); amber.setFill(); path.fill()
}
mark(64,61,36)
text("yapp", 113, 54, .systemFont(ofSize: 39, weight: .bold), ink)
text("Less clacking.", 64, 224, .systemFont(ofSize: 67, weight: .semibold), ink)
text("More yapping.", 64, 298, NSFont(name: "Georgia-Italic", size: 68)!, ink)
text("Free, offline, on-device dictation.", 67, 416, .systemFont(ofSize: 24), color(102,107,96))
text("yapp.now", 67, 550, .systemFont(ofSize: 21, weight: .medium), color(102,107,96))
color(28,28,30).setFill()
NSBezierPath(roundedRect: NSRect(x: 732, y: 258, width: 400, height: 134), xRadius: 67, yRadius: 67).fill()
mark(785,292,66)
amber.withAlphaComponent(0.78).setFill()
for (i,height) in [18,30,45,55,43,30,18].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 896+CGFloat(i)*22, y: 325-CGFloat(height)/2,
        width: 9, height: CGFloat(height)), xRadius: 4.5, yRadius: 4.5).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print(output.path)
