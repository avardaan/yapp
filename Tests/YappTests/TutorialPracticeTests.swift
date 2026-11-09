import XCTest
@testable import yapp

final class TutorialPracticeTests: XCTestCase {
    @MainActor
    func testLateAndStalePracticeResultsAreRejected() throws {
        let practice = TutorialPractice()
        practice.begin()
        let old = try XCTUnwrap(practice.id)
        practice.begin()
        XCTAssertFalse(practice.receive("Old result.", for: old))
        XCTAssertTrue(practice.text.isEmpty)
        let id = try XCTUnwrap(practice.id)
        XCTAssertTrue(practice.receive("Current.", for: id))
        XCTAssertEqual(practice.text, "Current.")
        practice.end()
        XCTAssertTrue(practice.text.isEmpty)
        XCTAssertFalse(practice.receive("Late result.", for: id))
        XCTAssertTrue(practice.text.isEmpty)
    }
}
