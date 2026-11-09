import AppKit
import OSLog
import UniformTypeIdentifiers

/// One fixed, content-free local event stream. Nothing is uploaded.
@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()
    enum Severity: String, Codable { case normal, error, fault }
    struct Event: Codable {
        let timestamp: Date
        let elapsedMS: Double
        let appSession: String
        let dictation: Int?
        let category: String
        let event: String
        let severity: Severity
        let fields: [String: String]
    }
    private let capacity: Int
    private let started = ProcessInfo.processInfo.systemUptime
    private let appSession = UUID().uuidString
    private var loggers: [String: Logger] = [:]
    @Published private(set) var events: [Event] = []
    private(set) var droppedEvents = 0

    init(defaults: UserDefaults = .standard, capacity: Int = 1000) {
        self.capacity = max(1, capacity)
        // Discard the obsolete verbosity preference from earlier local builds.
        defaults.removeObject(forKey: "diagnosticsMode")
    }

    /// Fields must be controlled metadata only: never user text, paths, or error descriptions.
    func record(_ event: String, category: String, dictation: Int? = nil,
                severity: Severity = .normal, fields: [String: String] = [:]) {
        let entry = Event(timestamp: Date(), elapsedMS: Self.milliseconds(since: started),
                          appSession: appSession, dictation: dictation, category: category,
                          event: event, severity: severity, fields: fields)
        if events.count == capacity { events.removeFirst(); droppedEvents += 1 }
        events.append(entry)
        let logger = loggers[category] ?? Logger(subsystem: "com.zeroslop.yapp", category: category)
        loggers[category] = logger
        let metadata = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let message = "\(event) app_session=\(appSession) dictation=\(dictation.map(String.init) ?? "-") \(metadata)"
        switch severity {
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        case .normal: logger.notice("\(message, privacy: .public)")
        }
    }

    static func milliseconds(since start: TimeInterval) -> Double {
        ((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded()
    }

    /// App-level context (launch, model, permissions) plus every event of the latest
    /// `dictations` dictations, as the same JSON Lines format as the file export.
    func recentData(dictations: Int) throws -> Data {
        let recent = Set(events.compactMap(\.dictation).reversed().reduce(into: [Int]()) {
            if $0.count < dictations, !$0.contains($1) { $0.append($1) }
        })
        return try exportData(events.filter { $0.dictation.map(recent.contains) ?? true },
                              scope: "Current app session; app events plus the latest \(dictations) dictations. No speech or transcripts.")
    }

    func exportData() throws -> Data {
        try exportData(events, scope: "Current app session; bounded to latest \(capacity) events. No speech or transcripts.")
    }

    private func exportData(_ events: [Event], scope: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let info = Bundle.main.infoDictionary ?? [:]
        var data = try encoder.encode([
            "event": "diagnostics.export", "schema": "2", "app_session": appSession,
            "version": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info["CFBundleVersion"] as? String ?? "unknown",
            "dropped_events": String(droppedEvents),
            "scope": scope
        ])
        data.append(0x0a)
        for event in events {
            data.append(try encoder.encode(event)); data.append(0x0a)
        }
        return data
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "yapp-Diagnostics.jsonl"
        panel.allowedContentTypes = [.data]
        panel.message = "Save local diagnostics from this launch. No audio, transcripts, or clipboard contents are included."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try self.exportData().write(to: url, options: .atomic) }
            catch {
                self.record("export.failed", category: "Diagnostics", severity: .error)
                let alert = NSAlert()
                alert.messageText = "Could not save diagnostics"
                alert.informativeText = "Choose another location and try again."
                alert.runModal()
            }
        }
    }
}
