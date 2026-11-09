import XCTest
import AppKit
@testable import yapp

final class TutorialPracticeTests: XCTestCase {
    @MainActor
    func testPracticeReplacesPreviousTextOnlyForCurrentTutorial() throws {
        let practice = TutorialPractice()
        practice.begin()
        let id = try XCTUnwrap(practice.id)
        XCTAssertTrue(practice.receive("First try.", for: id))
        XCTAssertTrue(practice.receive("Second try.", for: id))
        XCTAssertEqual(practice.text, "Second try.")
        practice.end()
        XCTAssertTrue(practice.text.isEmpty)
        XCTAssertFalse(practice.receive("Late result.", for: id))
        XCTAssertTrue(practice.text.isEmpty)
    }

    @MainActor
    func testReplayRejectsPreviousInFlightResult() throws {
        let practice = TutorialPractice()
        practice.begin()
        let old = try XCTUnwrap(practice.id)
        practice.begin()
        XCTAssertFalse(practice.receive("Old result.", for: old))
        XCTAssertTrue(practice.text.isEmpty)
        XCTAssertNotEqual(practice.id, old)
    }
    @MainActor
    func testFreshLaunchSchedulesTutorialAndCompletedLaunchDoesNot() {
        let name = "YappTutorialTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let guide = FirstLaunchGuide(defaults: defaults)
        guide.start()
        XCTAssertTrue(guide.isPending)
        guide.shutdown()
        defaults.set(true, forKey: "completedFirstLaunchGuide")
        guide.start()
        XCTAssertFalse(guide.isPending)
        guide.replay()
        XCTAssertTrue(guide.isPending)
        guide.shutdown()
    }

    func testStagesFollowRealCaptureAndTranscriptionBeforeShowingResult() {
        XCTAssertEqual(TutorialStage.resolve(phase: .ready, hasText: false), .prompt)
        XCTAssertEqual(TutorialStage.resolve(phase: .recording, hasText: true), .listening)
        XCTAssertEqual(TutorialStage.resolve(phase: .transcribing, hasText: true), .processing)
        XCTAssertEqual(TutorialStage.resolve(phase: .ready, hasText: true), .result)
        XCTAssertEqual(TutorialStage.resolve(phase: .loading, hasText: false), .preparing)
    }

    @MainActor
    func testPracticeAreaIsCenteredAndLeavesRoomForRealFloaty() {
        for size in [NSSize(width: 1440, height: 900), NSSize(width: 640, height: 480)] {
            let bounds = NSRect(origin: .zero, size: size)
            let frame = GuideCanvas.practiceFrame(in: bounds)
            XCTAssertTrue(bounds.contains(frame))
            XCTAssertEqual(frame.midX, bounds.midX)
            XCTAssertGreaterThan(frame.minY, 180)
            XCTAssertLessThan(frame.maxY + 90, bounds.maxY)
        }
    }

    @MainActor
    func testMenuCalloutUsesOnlyIconBounds() {
        let host = NSRect(x: 100, y: 800, width: 80, height: 30)
        let icon = MenuBarIconAnchor.iconFrame(in: host)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(icon.midX, host.midX)
        XCTAssertEqual(icon.midY, host.midY)
        XCTAssertTrue(host.contains(icon))
    }

    @MainActor
    func testPreparationIsOnlyBeforePracticeBegins() {
        let practice = TutorialPractice()
        practice.begin()
        XCTAssertFalse(practice.isPrepared)
        XCTAssertEqual(TutorialStage.resolve(phase: .loading, hasText: false, hasPrepared: practice.isPrepared), .preparing)
        practice.markPrepared()
        XCTAssertTrue(practice.isPrepared)
        XCTAssertEqual(TutorialStage.resolve(phase: .loading, hasText: false, hasPrepared: practice.isPrepared), .prompt)
        XCTAssertEqual(TutorialStage.resolve(phase: .requestingPermission, hasText: false, hasPrepared: practice.isPrepared), .prompt)
        practice.end()
        XCTAssertFalse(practice.isPrepared)
    }

}
