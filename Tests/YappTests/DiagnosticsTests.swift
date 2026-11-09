import XCTest
@testable import yapp

final class DiagnosticsTests: XCTestCase {
    @MainActor
    func testFixedStreamKeepsLifecycleEventsAndFailuresRegardlessOfLegacyMode() {
        let name = "YappDiagnosticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for legacyMode in ["standard", "debug"] {
            defaults.set(legacyMode, forKey: "diagnosticsMode")
            let diagnostics = Diagnostics(defaults: defaults)
            diagnostics.record("capture.started", category: "Test", dictation: 1)
            diagnostics.record("dictation.completed", category: "Test", dictation: 1)
            diagnostics.record("operation.failed", category: "Test", severity: .error)
            XCTAssertEqual(diagnostics.events.map(\.event), ["capture.started", "dictation.completed", "operation.failed"])
            XCTAssertEqual(diagnostics.events.first?.dictation, 1)
            XCTAssertNil(defaults.object(forKey: "diagnosticsMode"))
        }
    }

    @MainActor
    func testExportIsBoundedValidJSONLinesWithoutVerbosityFields() throws {
        let diagnostics = Diagnostics(capacity: 2)
        diagnostics.record("capture.started", category: "Test", dictation: 2)
        diagnostics.record("capture.ended", category: "Test", dictation: 2)
        diagnostics.record("dictation.completed", category: "Test", dictation: 2, fields: ["outcome": "silence_rejected"])
        XCTAssertEqual(diagnostics.events.map(\.event), ["capture.ended", "dictation.completed"])
        XCTAssertEqual(diagnostics.droppedEvents, 1)
        let lines = try XCTUnwrap(String(data: diagnostics.exportData(), encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let objects = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(objects[0]["schema"] as? String, "2")
        XCTAssertTrue(objects.allSatisfy { $0["mode"] == nil && $0["detail"] == nil })
        XCTAssertTrue(diagnostics.events.allSatisfy { $0.elapsedMS >= 0 })
        XCTAssertEqual(Set(diagnostics.events.map(\.appSession)).count, 1)
    }

    @MainActor
    func testQuickTapHasExactlyOneTerminalOutcome() {
        let diagnostics = Diagnostics.shared
        let before = diagnostics.events.count
        let session = DictationSession()
        session.phase = .ready
        session.shortcutPressed()
        session.shortcutReleased()
        session.cancelShortcut()
        session.shutdown()
        let completed = diagnostics.events.dropFirst(before).filter { $0.event == "dictation.completed" }
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.fields["outcome"], "cancelled_before_capture")
        XCTAssertEqual(completed.first?.dictation, 1)
    }

    @MainActor
    func testPressDuringLoadingCompletesCancelledDictation() {
        let diagnostics = Diagnostics.shared
        let before = diagnostics.events.count
        let session = DictationSession()
        session.shortcutPressed()
        session.shortcutReleased()
        session.shutdown()
        let completed = diagnostics.events.dropFirst(before).filter { $0.event == "dictation.completed" }
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.fields["outcome"], "cancelled_before_capture")
    }
}
