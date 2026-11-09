import SwiftUI

/// Live table of this launch's local diagnostics stream. Content-free by construction.
struct DiagnosticsLogView: View {
    static let windowID = "diagnostics-log"
    static let copiedDictations = 5
    @ObservedObject private var diagnostics = Diagnostics.shared
    @State private var copied = false

    struct Row: Identifiable {
        let id: Int
        let event: Diagnostics.Event
        var timestamp: String { String(Int64((event.timestamp.timeIntervalSince1970 * 1000).rounded())) }
        var dictation: String { event.dictation?.uuidString.lowercased() ?? "—" }
        var fields: String { event.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") }
    }

    var body: some View {
        let rows = diagnostics.events.enumerated().map { Row(id: $0.offset, event: $0.element) }
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Table(rows) {
                    TableColumn("timestamp (ms)") { cell($0.timestamp, $0) }.width(min: 110, ideal: 115)
                    TableColumn("dictation_id") { cell($0.dictation, $0) }.width(min: 120, ideal: 260)
                    TableColumn("category") { cell($0.event.category, $0) }.width(min: 70, ideal: 90)
                    TableColumn("event") { cell($0.event.event, $0) }.width(min: 110, ideal: 160)
                    TableColumn("fields") { cell($0.fields, $0) }
                }
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: rows.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
                .onAppear { proxy.scrollTo(rows.count - 1, anchor: .bottom) }
            }
            Divider()
            HStack {
                Text("No audio, transcripts, or clipboard contents.").foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy Last \(Self.copiedDictations) Dictations") { copy() }
            }
            .padding(12)
        }
        .frame(minWidth: 900, minHeight: 360)
    }

    private func cell(_ text: String, _ row: Row) -> some View {
        Text(text).foregroundStyle(row.event.severity == .normal ? .primary : Color.red).textSelection(.enabled)
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
}
