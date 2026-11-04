import AppKit

@MainActor
enum AboutPanel {
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
            .applicationIcon: YappMark.aboutImage,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
