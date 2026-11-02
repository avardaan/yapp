import SwiftUI
import AVFoundation

struct YappMenu: View {
    @ObservedObject var session: DictationSession
    @ObservedObject private var shortcut = FnShortcut.shared
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("About") {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationIcon: YappMark.aboutImage,
                .credits: NSAttributedString(string: "Private, offline dictation.\nHold your shortcut to talk.\nRelease to insert.\nMade by zeroslop.")
            ])
            NSApp.activate(ignoringOtherApps: true)
        }
        Menu("Status") {
            ForEach(Array(statusLines.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
            Button("Copy Status Details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.status, forType: .string)
            }
        }
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
            Text(TextInsertion.allowed ? "Text Insertion: Allowed" : "Text Insertion: Not Allowed")
            Button("Enable Text Insertion…") { TextInsertion.requestPermission() }
            Button("Accessibility Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }
            Button("Microphone Settings…") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
                NSWorkspace.shared.open(url)
            }
        }
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates || session.phase == .recording || session.phase == .transcribing)
        Button("Quit") { NSApp.terminate(nil) }
    }

    // Long errors stay accessible inside the menu; no auxiliary windows.
    private var statusLines: [String] {
        var remaining = session.status[...]
        var lines: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(30, remaining.count))
            lines.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return lines
    }

    private var microphoneStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Microphone: Allowed"
        case .denied: return "Microphone: Denied"
        case .restricted: return "Microphone: Restricted"
        case .notDetermined: return "Microphone: Not Requested"
        @unknown default: return "Microphone: Unknown"
        }
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
