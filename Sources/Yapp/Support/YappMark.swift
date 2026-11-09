import AppKit

@MainActor
enum YappMark {
    static var aboutImage: NSImage {
        NSImage(named: "yapp") ?? NSApp.applicationIconImage
    }

    static func menuImage(shortcutHeld: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.labelColor.setFill()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            if shortcutHeld {
                let mouth = NSBezierPath()
                mouth.move(to: center)
                mouth.appendArc(withCenter: center, radius: 8, startAngle: 28, endAngle: 332, clockwise: false)
                mouth.close()
                mouth.fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)).fill()
                // Cut a fine mouth slit into the template alpha so it adapts to
                // light/dark menu bars and the menu item's selected appearance.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                let mouth = NSBezierPath()
                mouth.move(to: center)
                mouth.line(to: NSPoint(x: center.x + 8.5, y: center.y))
                mouth.lineWidth = 1.1
                mouth.lineCapStyle = .round
                mouth.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
