import SwiftUI
import AVFoundation

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
                .background(StatusItemAnchor())
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
        if CommandLine.arguments.contains("--about") { AboutPanel.show() }
        FirstLaunchGuide.shared.start()
        requestLaunchPermissions()
        Task { await DictationSession.shared.prepare() }
    }

    private func requestLaunchPermissions() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            FnShortcut.shared.start()
            return
        }
        // Request access at first launch without starting capture. Serialize the
        // native prompts so Accessibility does not compete with Microphone.
        // Keep the callback API: the async SDK bridge previously crashed here.
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                FnShortcut.shared.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FirstLaunchGuide.shared.shutdown()
        ActivityIndicator.shared.shutdown()
        FnShortcut.shared.shutdown()
        DictationSession.shared.shutdown()
    }
}
