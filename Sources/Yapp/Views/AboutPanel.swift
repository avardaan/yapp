import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(string: "Private, offline dictation.\nHold your shortcut to talk.\nRelease to insert.\nMade by ")
        credits.append(NSAttributedString(string: "Vardaan", attributes: [
            .link: URL(string: "https://github.com/avardaan")!,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        credits.append(NSAttributedString(string: "."))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: YappMark.aboutImage,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
