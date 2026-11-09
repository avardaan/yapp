import XCTest
@testable import Yapp

final class TutorialPracticeTests: XCTestCase {
    @MainActor
    func testPracticeAccumulatesOnlyForCurrentTutorial() throws {
        let practice = TutorialPractice()
        practice.begin()
        let id = try XCTUnwrap(practice.id)
        XCTAssertTrue(practice.receive("First try.", for: id))
        XCTAssertTrue(practice.receive("Second try.", for: id))
        XCTAssertEqual(practice.text, "First try.\nSecond try.")
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

}
