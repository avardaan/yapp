import SwiftUI

/// Live view of this launch's local diagnostics stream. Content-free by construction.
struct DiagnosticsLogView: View {
    static let windowID = "diagnostics-log"
    static let copiedDictations = 5
    @ObservedObject private var diagnostics = Diagnostics.shared
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(Array(diagnostics.events.enumerated()), id: \.offset) { index, event in
                    Text(Self.line(event))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(event.severity == .normal ? .primary : Color.red)
                        .textSelection(.enabled)
                        .id(index)
                }
                .onChange(of: diagnostics.events.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
                .onAppear { proxy.scrollTo(diagnostics.events.count - 1, anchor: .bottom) }
            }
            Divider()
            HStack {
                Text("No audio, transcripts, or clipboard contents.").foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy Last \(Self.copiedDictations) Dictations") { copy() }
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private func copy() {
        guard let data = try? diagnostics.recentData(dictations: Self.copiedDictations),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        diagnostics.record("log.copied", category: "Diagnostics")
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private static func line(_ event: Diagnostics.Event) -> String {
        let fields = event.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let time = String(format: "%9.1fs", event.elapsedMS / 1000)
        return "\(time)  #\(event.dictation.map(String.init) ?? "-")  \(event.category)  \(event.event)  \(fields)"
    }
}
