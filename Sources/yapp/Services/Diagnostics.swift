import AppKit
import OSLog
import UniformTypeIdentifiers

/// One fixed, content-free local event stream. Nothing is uploaded.
@MainActor
final class Diagnostics {
    static let shared = Diagnostics()
    enum Severity: String, Codable { case normal, error, fault }
    struct Event: Codable {
        let timestamp: Date
        let elapsedMS: Double
        let appSession: String
        let dictation: UUID?
        let category: String
        let event: String
        let severity: Severity
        let fields: [String: String]
    }
    private let capacity: Int
    private let started = ProcessInfo.processInfo.systemUptime
    private let appSession = UUID().uuidString
    private var loggers: [String: Logger] = [:]
    private(set) var events: [Event] = []
    private(set) var droppedEvents = 0

    init(defaults: UserDefaults = .standard, capacity: Int = 1000) {
        self.capacity = max(1, capacity)
        // Discard the obsolete verbosity preference from earlier local builds.
        defaults.removeObject(forKey: "diagnosticsMode")
    }

    /// Fields must be controlled metadata only: never user text, paths, or error descriptions.
    func record(_ event: String, category: String, dictation: UUID? = nil,
                severity: Severity = .normal, fields: [String: String] = [:]) {
        let entry = Event(timestamp: Date(), elapsedMS: Self.milliseconds(since: started),
                          appSession: appSession, dictation: dictation, category: category,
                          event: event, severity: severity, fields: fields)
        if events.count == capacity { events.removeFirst(); droppedEvents += 1 }
        events.append(entry)
        let logger = loggers[category] ?? Logger(subsystem: "com.zeroslop.yapp", category: category)
        loggers[category] = logger
        let metadata = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let message = "\(event) app_session=\(appSession) dictation=\(dictation?.uuidString.lowercased() ?? "-") \(metadata)"
        switch severity {
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        case .normal: logger.notice("\(message, privacy: .public)")
        }
    }

    static func milliseconds(since start: TimeInterval) -> Double {
        ((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded()
    }

    /// Every event, dictation or not, after the last event of the dictation just before the
    /// latest `dictations` ones; the whole launch if there are fewer. Same JSON Lines format.
    func recentData(dictations: Int) throws -> Data {
        var seen: [UUID] = []
        var start = events.startIndex
        for index in events.indices.reversed() {
            guard let id = events[index].dictation, !seen.contains(id) else { continue }
            if seen.count == dictations { start = index + 1; break }
            seen.append(id)
        }
        return try exportData(Array(events[start...]),
                              scope: "Current app session; all events since before the latest \(dictations) dictations. No speech or transcripts.")
    }

    static let copiedDictations = 10

    func copyRecent() {
        guard let data = try? recentData(dictations: Self.copiedDictations),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        record("log.copied", category: "Diagnostics")
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
            "event": "diagnostics.export", "schema": "3", "app_session": appSession,
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

extension UUID {
    /// RFC 9562 version 7: 48-bit Unix milliseconds then random bits, so IDs sort by time.
    static func v7(now: Date = Date()) -> UUID {
        var bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        let ms = UInt64(now.timeIntervalSince1970 * 1000)
        for i in 0..<6 { bytes[i] = UInt8(truncatingIfNeeded: ms >> (40 - 8 * i)) }
        bytes[6] = 0x70 | (bytes[6] & 0x0f)
        bytes[8] = 0x80 | (bytes[8] & 0x3f)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
