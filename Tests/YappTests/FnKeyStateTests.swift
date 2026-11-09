import XCTest
@testable import yapp

final class ShortcutKeyStateTests: XCTestCase {
    func testPhysicalFnPressAndRelease() {
        var state = ShortcutKeyState()
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: true), .pressed)
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: true))
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: false), .released)
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: false))
    }
    func testChordCancelsInsteadOfTranscribing() {
        var state = ShortcutKeyState()
        _ = state.flagsChanged(keyCode: 63, isDown: true)
        XCTAssertEqual(state.otherKeyPressed(), .cancelled)
        XCTAssertNil(state.otherKeyPressed())
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: false))
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: true), .pressed)
    }
    func testLostReleaseResetsForNextPress() {
        var state = ShortcutKeyState()
        _ = state.flagsChanged(keyCode: 63, isDown: true)
        XCTAssertEqual(state.reset(), .cancelled)
        XCTAssertFalse(state.held)
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: false))
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: true), .pressed)
    }
}
