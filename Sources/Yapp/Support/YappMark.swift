import AppKit

@MainActor
enum YappMark {
    static let aboutImage = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
        NSColor(calibratedRed: 0.88, green: 0.76, blue: 0.38, alpha: 1).setFill()
        let center = NSPoint(x: 32, y: 32)
        let path = NSBezierPath()
        path.move(to: center)
        path.appendArc(withCenter: center, radius: 27, startAngle: 28, endAngle: 332, clockwise: false)
        path.close()
        path.fill()
        return true
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
