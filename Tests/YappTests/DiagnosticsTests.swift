import XCTest
@testable import yapp

final class DiagnosticsTests: XCTestCase {
    /// Copy covers a contiguous window: app events between and after the latest N
    /// dictations are kept; everything up to the end of dictation N+1 is dropped.
    @MainActor
    func testRecentCopyKeepsContiguousWindowOfLatestDictations() throws {
        let diagnostics = Diagnostics(capacity: 100)
        let ids = (0..<4).map { _ in UUID.v7() }
        diagnostics.record("app.before", category: "Test")
        for (n, id) in ids.enumerated() {
            diagnostics.record("dictation.started", category: "Test", dictation: id)
            diagnostics.record("dictation.completed", category: "Test", dictation: id)
            diagnostics.record("app.after.\(n)", category: "Test")
        }
        let lines = try XCTUnwrap(String(data: diagnostics.recentData(dictations: 2), encoding: .utf8))
            .split(separator: "\n").dropFirst()
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])["event"] as? String }
        XCTAssertEqual(lines, ["app.after.1", "dictation.started", "dictation.completed", "app.after.2",
                               "dictation.started", "dictation.completed", "app.after.3"])
        let all = try XCTUnwrap(String(data: diagnostics.recentData(dictations: 10), encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(all.count, 1 + diagnostics.events.count)
    }
}
