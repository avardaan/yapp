import SwiftUI

/// Live view of this launch's local diagnostics stream, grouped by dictation. Content-free by construction.
struct DiagnosticsLogView: View {
    static let windowID = "diagnostics-log"
    static let copiedDictations = 5
    @ObservedObject private var diagnostics = Diagnostics.shared
    @State private var copied = false

    /// A run of app-level events, or every event of one dictation (kept together even if app events interleave).
    struct Group: Identifiable {
        let id: Int
        let dictation: UUID?
        var events: [Diagnostics.Event]
    }

    static func groups(_ events: [Diagnostics.Event]) -> [Group] {
        var groups: [Group] = []
        var index: [UUID: Int] = [:]
        for event in events {
            if let dictation = event.dictation, let i = index[dictation] { groups[i].events.append(event); continue }
            if event.dictation == nil, let last = groups.indices.last, groups[last].dictation == nil {
                groups[last].events.append(event); continue
            }
            if let dictation = event.dictation { index[dictation] = groups.count }
            groups.append(Group(id: groups.count, dictation: event.dictation, events: [event]))
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Self.groups(diagnostics.events)) { group in
                        Section { ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in row(event) } }
                            header: { header(group) }
                            .id(group.id)
                    }
                }
                .onChange(of: diagnostics.events.count) { _, _ in scrollToEnd(proxy) }
                .onAppear { scrollToEnd(proxy) }
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

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = Self.groups(diagnostics.events).last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    @ViewBuilder private func header(_ group: Group) -> some View {
        if let dictation = group.dictation {
            let completed = group.events.last { $0.event == "dictation.completed" }
            let start = group.events[0].timestamp.formatted(date: .omitted, time: .standard)
            let summary = completed.map { done in
                [done.fields["outcome"], done.fields["duration_ms"].flatMap(Double.init).map { String(format: "%.1f s", $0 / 1000) }]
                    .compactMap { $0 }.joined(separator: " · ")
            } ?? "in progress"
            HStack {
                Text("Dictation · \(start) · \(summary)").fontWeight(.semibold)
                Spacer()
                Text(dictation.uuidString.lowercased()).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        } else {
            Text("App").fontWeight(.semibold)
        }
    }

    private func row(_ event: Diagnostics.Event) -> some View {
        let fields = event.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return Text("\(Int64((event.timestamp.timeIntervalSince1970 * 1000).rounded()))  \(event.category)  \(event.event)  \(fields)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(event.severity == .normal ? .primary : Color.red)
            .textSelection(.enabled)
            .padding(.leading, 16)
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
