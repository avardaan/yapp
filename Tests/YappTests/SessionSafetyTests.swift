import XCTest
@testable import yapp

final class SessionSafetyTests: XCTestCase {
    @MainActor
    func testReleaseOrCancelBeforeReadyNeverStartsCapture() async throws {
        for interrupt in [{ (s: DictationSession) in s.shortcutReleased() }, { $0.cancelShortcut() }] {
            let session = DictationSession()
            session.shortcutPressed()
            interrupt(session)
            session.modelBecameReady()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(session.phase, .ready)
            XCTAssertFalse(session.waitingForModel)
            session.shutdown()
        }
    }

    @MainActor
    func testQuickTapDoesNotRecord() async throws {
        let session = DictationSession()
        session.phase = .ready
        session.shortcutPressed()
        session.shortcutReleased()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.transcript.isEmpty)
        session.shutdown()
    }
}
