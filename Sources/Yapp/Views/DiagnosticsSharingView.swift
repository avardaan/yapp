import SwiftUI

/// Consent surface only. No sharing session or network client exists yet.
struct DiagnosticsSharingView: View {
    static let windowID = "diagnostics-sharing"
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Share diagnostics")
                    .font(.title2.weight(.semibold))
                Text("Help improve Yapp by sharing diagnostic logs.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("App version, model loading times, and dictation outcomes.", systemImage: "waveform.path")
                Label("No audio, transcripts, or clipboard contents are included.", systemImage: "lock.shield")
            }
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Sharing is off")
                    .fontWeight(.medium)
                Text("Diagnostic sharing isn’t available yet. Nothing is being sent.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Close") { dismissWindow(id: Self.windowID) }
                    .keyboardShortcut(.cancelAction)
                Button("Start Sharing") { }
                    .disabled(true)
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(width: 400, alignment: .leading)
        .onAppear {
            Diagnostics.shared.record("sharing.dialog_opened", category: "Diagnostics")
        }
        .onDisappear {
            Diagnostics.shared.record("sharing.dialog_closed", category: "Diagnostics")
        }
    }
}
