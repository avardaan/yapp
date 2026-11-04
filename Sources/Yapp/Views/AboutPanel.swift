import AppKit

@MainActor
enum AboutPanel {
    // Give the charcoal tile a quiet edge against the About panel in either appearance.
    private static var outlinedIcon: NSImage {
        let base = YappMark.aboutImage
        return NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            base.draw(in: rect)
            // Match the approved icon vector's tile bounds and corner radius.
            let tile = NSRect(x: 9.5, y: 9.5, width: 109, height: 109)
            let outline = NSBezierPath(roundedRect: tile, xRadius: 24.375, yRadius: 24.375)
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            outline.lineWidth = 0.75
            outline.stroke()
            return true
        }
    }

    static func show() {
        let credits = NSMutableAttributedString(string: "Private, offline dictation.\n\nCrafted with care by ")
        credits.append(NSAttributedString(string: "Vardaan", attributes: [
            .link: URL(string: "https://github.com/avardaan")!,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        credits.append(NSAttributedString(string: "."))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        credits.addAttributes([
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .paragraphStyle: paragraph
        ], range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: outlinedIcon,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
