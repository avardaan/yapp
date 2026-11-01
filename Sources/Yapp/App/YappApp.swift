import SwiftUI

@main
struct YappApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var session = DictationSession.shared

    var body: some Scene {
        MenuBarExtra {
            YappMenu(session: session)
        } label: {
            Label { Text("Yapp — \(session.menuStatus)") } icon: { Image(nsImage: YappMark.menuImage(for: session.phase)) }
                .accessibilityLabel("Yapp — \(session.menuStatus)")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only is intentional: no windows and no Dock activation.
        NSApp.setActivationPolicy(.accessory)
        ActivityIndicator.shared.start(session: DictationSession.shared)
        FnShortcut.shared.start()
        Task { await DictationSession.shared.prepare() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActivityIndicator.shared.shutdown()
        FnShortcut.shared.shutdown()
        DictationSession.shared.shutdown()
    }
}
