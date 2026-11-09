import SwiftUI
import AVFoundation

struct YappMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var session: DictationSession
    @ObservedObject private var shortcut = FnShortcut.shared
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("About") { AboutPanel.show() }
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates || session.phase == .recording || session.phase == .transcribing)
        Divider()
        Menu("Shortcut") {
            Text("\(shortcut.selected.title) · Hold to talk")
            Menu("Change Shortcut…") {
                Picker("Shortcut", selection: Binding(get: { shortcut.selected }, set: { shortcut.select($0) })) {
                    ForEach(DictationShortcut.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        Menu("Permissions") {
            Text(microphoneStatus)
            Button("Microphone Settings…") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
                NSWorkspace.shared.open(url)
            }
            Text(TextInsertion.allowed ? "Accessibility: Allowed" : "Accessibility: Disabled")
            Button("Accessibility Settings…") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
                NSWorkspace.shared.open(url)
            }
        }
        Menu("Advanced") {
            Button("Show Sonoscope") { }
                .disabled(true)
            Menu("Diagnostics") {
                Button("Show Log") {
                    openWindow(id: DiagnosticsLogView.windowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Share Diagnostics…") {
                    openWindow(id: DiagnosticsSharingView.windowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .disabled(true)
            }
            Button("Show Tutorial") { FirstLaunchGuide.shared.replay() }
        }
        Button("Quit") { NSApp.terminate(nil) }
    }

    private var microphoneStatus: String {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? "Microphone: Allowed" : "Microphone: Disabled"
    }

}

extension DictationSession {
    var menuStatus: String {
        switch phase {
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .requestingPermission: return "Microphone Access"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .failed: return "Model Error"
        }
    }

    var menuSymbol: String {
        switch phase {
        case .loading, .transcribing: return "hourglass"
        case .recording: return "record.circle.fill"
        case .requestingPermission, .failed: return "exclamationmark.circle"
        case .ready: return "waveform"
        }
    }
}
