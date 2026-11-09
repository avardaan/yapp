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
            Label { Text("yapp — \(session.menuStatus)") } icon: { Image(nsImage: YappMark.menuImage(shortcutHeld: session.shortcutOwnsRecording)) }
                .accessibilityLabel("yapp — \(session.menuStatus)")
                .background(MenuBarIconAnchor().frame(width: 18, height: 18))
        }
        .menuBarExtraStyle(.menu)

        Window("Share Diagnostics", id: DiagnosticsSharingView.windowID) {
            DiagnosticsSharingView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only is intentional: utility dialogs open on demand, with no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        Diagnostics.shared.record("app.launched", category: "Lifecycle", fields: [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        ])
        ActivityIndicator.shared.start(session: DictationSession.shared)
        if CommandLine.arguments.contains("--about") { AboutPanel.show() }
        FirstLaunchGuide.shared.start()
        requestLaunchPermissions()
        Task { await DictationSession.shared.prepare() }
    }

    private func requestLaunchPermissions() {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        Diagnostics.shared.record("permissions.checked", category: "Permissions", fields: [
            "microphone": String(microphone.rawValue), "accessibility": String(TextInsertion.allowed)
        ])
        guard microphone == .notDetermined else {
            FnShortcut.shared.start()
            return
        }
        // Request access at first launch without starting capture. Serialize the
        // native prompts so Accessibility does not compete with Microphone.
        // Keep the callback API: the async SDK bridge previously crashed here.
        Diagnostics.shared.record("microphone.requested", category: "Permissions")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                Diagnostics.shared.record("microphone.result", category: "Permissions", fields: ["allowed": String(granted)])
                FnShortcut.shared.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FirstLaunchGuide.shared.shutdown()
        ActivityIndicator.shared.shutdown()
        FnShortcut.shared.shutdown()
        DictationSession.shared.shutdown()
        Diagnostics.shared.record("app.terminated", category: "Lifecycle")
    }
}
