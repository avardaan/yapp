import XCTest
@testable import Yapp

final class ShortcutKeyStateTests: XCTestCase {
    func testPhysicalFnPressAndRelease() {
        var state = ShortcutKeyState()
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: true), .pressed)
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: true))
        XCTAssertEqual(state.flagsChanged(keyCode: 63, isDown: false), .released)
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: false))
    }
    func testArrowFnFlagDoesNotStartRecording() {
        var state = ShortcutKeyState()
        XCTAssertNil(state.flagsChanged(keyCode: 126, isDown: true))
        XCTAssertFalse(state.held)
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
    func testRightOptionUsesItsOwnPhysicalKey() {
        var state = ShortcutKeyState()
        XCTAssertNil(state.flagsChanged(keyCode: 58, isDown: true, triggerKeyCode: 61))
        XCTAssertNil(state.flagsChanged(keyCode: 63, isDown: true, triggerKeyCode: 61))
        XCTAssertEqual(state.flagsChanged(keyCode: 61, isDown: true, triggerKeyCode: 61), .pressed)
        XCTAssertEqual(state.flagsChanged(keyCode: 61, isDown: false, triggerKeyCode: 61), .released)
    }

    func testRightControlChordCannotBecomeDictationOnRelease() {
        var state = ShortcutKeyState()
        XCTAssertEqual(state.flagsChanged(keyCode: 62, isDown: true, triggerKeyCode: 62), .pressed)
        XCTAssertEqual(state.otherKeyPressed(), .cancelled)
        XCTAssertNil(state.flagsChanged(keyCode: 62, isDown: false, triggerKeyCode: 62))
        XCTAssertEqual(state.flagsChanged(keyCode: 62, isDown: true, triggerKeyCode: 62), .pressed)
    }
}
