import XCTest
import AppKit
@testable import Yapp

final class DictationLifecycleTests: XCTestCase {
    @MainActor
    func testQuickTapDoesNotRequestMicrophone() async throws {
        let session = DictationSession()
        session.phase = .ready
        session.shortcutPressed()
        session.shortcutReleased()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.transcript.isEmpty)
    }

    @MainActor
    func testShortcutDoesNotStopManualRecording() {
        let session = DictationSession()
        session.phase = .recording
        session.shortcutPressed()
        session.shortcutReleased()
        session.cancelShortcut()
        XCTAssertEqual(session.phase, .recording)
    }

    @MainActor
    func testCancelledHoldDoesNotStartLater() async throws {
        let session = DictationSession()
        session.phase = .ready
        session.shortcutPressed()
        session.cancelShortcut()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(session.phase, .ready)
    }

    @MainActor
    func testIndicatorIsNonactivatingAndHidesAfterProcessing() {
        let session = DictationSession()
        let indicator = ActivityIndicator()
        indicator.start(session: session)
        let before = Set(NSApplication.shared.windows.map(\.windowNumber))
        session.phase = .recording
        let panel = NSApplication.shared.windows.first { !before.contains($0.windowNumber) }
        XCTAssertNotNil(panel)
        XCTAssertEqual(panel?.frame.size, NSSize(width: 104, height: 38))
        XCTAssertEqual(panel?.ignoresMouseEvents, true)
        XCTAssertEqual(panel?.canBecomeKey, false)
        XCTAssertEqual(panel?.isVisible, true)
        session.phase = .transcribing
        XCTAssertEqual(panel?.isVisible, true)
        session.phase = .ready
        XCTAssertEqual(panel?.isVisible, false)
        indicator.shutdown()
    }
}
