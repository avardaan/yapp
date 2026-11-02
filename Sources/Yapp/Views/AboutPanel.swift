import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: YappMark.aboutImage,
            .credits: NSAttributedString(string: "Private, offline dictation.\nHold your shortcut to talk.\nRelease to insert.\nMade by zeroslop.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
