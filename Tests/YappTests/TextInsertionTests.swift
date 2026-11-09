import XCTest
import AppKit
import ApplicationServices
@testable import yapp

final class TextInsertionTests: XCTestCase {
    @MainActor
    func testMissingTargetNeverChangesClipboard() async {
        let revision = NSPasteboard.general.changeCount
        let result = await TextInsertion.insert("test dictation", into: nil)
        XCTAssertTrue(result?.contains("Copy Last Transcript") == true)
        XCTAssertEqual(NSPasteboard.general.changeCount, revision)
    }

    @MainActor
    func testStaleTargetNeverChangesClipboard() async {
        let revision = NSPasteboard.general.changeCount
        let invalid = TextInsertion.Target(processID: -1, element: AXUIElementCreateSystemWide())
        let result = await TextInsertion.insert("test dictation", into: invalid)
        XCTAssertTrue(result?.contains("Copy Last Transcript") == true)
        XCTAssertEqual(NSPasteboard.general.changeCount, revision)
    }

    @MainActor
    func testEmptyTranscriptIsNeverInserted() async {
        let revision = NSPasteboard.general.changeCount
        let result = await TextInsertion.insert("", into: nil)
        XCTAssertEqual(result, "No speech detected")
        XCTAssertEqual(NSPasteboard.general.changeCount, revision)
    }
}
