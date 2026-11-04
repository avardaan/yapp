import XCTest
@testable import Yapp

final class DiagnosticsTests: XCTestCase {
    @MainActor
    func testStandardFiltersDetailsButKeepsFailures() throws {
        let name = "YappDiagnosticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let diagnostics = Diagnostics(defaults: defaults)
        diagnostics.record("capture.started", category: "Test", detail: true)
        diagnostics.record("dictation.completed", category: "Test", dictation: 1)
        diagnostics.record("operation.failed", category: "Test", detail: true, severity: .error)
        XCTAssertEqual(diagnostics.events.map(\.event), ["dictation.completed", "operation.failed"])
        XCTAssertEqual(diagnostics.events.first?.dictation, 1)
    }

    @MainActor
    func testDebugPersistsAndExportIsBoundedValidJSONLines() throws {
        let name = "YappDiagnosticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let diagnostics = Diagnostics(defaults: defaults, capacity: 2)
        diagnostics.mode = .debug
        diagnostics.record("capture.started", category: "Test", dictation: 2, detail: true)
        diagnostics.record("dictation.completed", category: "Test", dictation: 2, fields: ["outcome": "silence_rejected"])
        XCTAssertEqual(diagnostics.events.count, 2)
        XCTAssertEqual(diagnostics.droppedEvents, 1)
        XCTAssertEqual(Diagnostics(defaults: defaults).mode, .debug)
        let lines = try XCTUnwrap(String(data: diagnostics.exportData(), encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
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
