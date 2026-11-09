import XCTest
@testable import yapp

final class LoadingShortcutTests: XCTestCase {
    @MainActor
    func testLoadingHoldShowsPreparationWithoutRecording() {
        let session = DictationSession()
        session.shortcutPressed()
        XCTAssertEqual(session.phase, .loading)
        XCTAssertTrue(session.waitingForModel)
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: session.phase, waiting: session.waitingForModel), .preparing)
        session.shortcutReleased()
        XCTAssertFalse(session.waitingForModel)
        XCTAssertEqual(session.phase, .loading)
        session.shutdown()
    }

    @MainActor
    func testReleaseBeforeReadyNeverStartsCapture() async throws {
        let session = DictationSession()
        session.shortcutPressed()
        session.shortcutReleased()
        session.modelBecameReady()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.waitingForModel)
        session.shutdown()
    }

    @MainActor
    func testReleaseAtReadinessCancelsQueuedCapture() async throws {
        let session = DictationSession()
        session.shortcutPressed()
        session.modelBecameReady()
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: session.phase, waiting: session.waitingForModel), .preparing)
        session.shortcutReleased()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.waitingForModel)
        session.shutdown()
    }

    @MainActor
    func testCancellationWhileLoadingNeverStartsCapture() async throws {
        let session = DictationSession()
        session.shortcutPressed()
        session.cancelShortcut()
        session.modelBecameReady()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertFalse(session.waitingForModel)
        session.shutdown()
    }

    @MainActor
    func testPresentationStaysVisibleThroughRecordingTransition() {
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: .ready, waiting: true), .preparing)
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: .requestingPermission, waiting: true), .preparing)
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: .recording, waiting: true), .recording)
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: .recording, waiting: false), .recording)
        XCTAssertEqual(ActivityIndicator.Presentation.resolve(phase: .loading, waiting: false), .hidden)
    }
}
