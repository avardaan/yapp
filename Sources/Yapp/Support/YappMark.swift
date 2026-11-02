import AppKit

@MainActor
enum YappMark {
    static var aboutImage: NSImage {
        NSImage(named: "Yapp") ?? NSApp.applicationIconImage
    }

    static func menuImage(for phase: DictationSession.Phase) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 18), flipped: false) { rect in
            NSColor.labelColor.setFill()
            let center = NSPoint(x: 8.5, y: 9)
            let path = NSBezierPath()
            path.move(to: center)
            let opening: CGFloat = phase == .recording ? 42 : 28
            path.appendArc(withCenter: center, radius: 8, startAngle: opening, endAngle: 360 - opening, clockwise: false)
            path.close()
            path.fill()
            if phase == .transcribing || phase == .loading {
                NSBezierPath(ovalIn: NSRect(x: 17, y: 7.5, width: 3, height: 3)).fill()
            } else if phase == .recording {
                NSBezierPath(ovalIn: NSRect(x: 17, y: 7, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
