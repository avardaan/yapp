import XCTest
@testable import yapp

final class SilenceTests: XCTestCase {
    func testNonSpeechLabelsRemovedAndSpeechKept() {
        for text in ["[Silence]", "[BLANK_AUDIO]", "(mouse clicking)", "*laughs*", "♪ ♪"] {
            XCTAssertEqual(DictationText.clean(text), "")
        }
        XCTAssertEqual(DictationText.clean("I prefer silence."), "I prefer silence.")
        XCTAssertEqual(DictationText.clean("[Silence] Hello there."), "Hello there.")
        XCTAssertEqual(DictationText.clean("I agree (laughs)."), "I agree.")
    }
    func testSilenceAndClickRejectedButQuietSpeechKept() {
        var samples = Array(repeating: Float(0), count: 16000)
        var silence = AudioActivity()
        samples.withUnsafeBufferPointer { silence.observe($0, sampleRate: 16000) }
        XCTAssertFalse(silence.hasActivity(sampleRate: 16000))
        samples[500] = 1
        var click = AudioActivity()
        samples.withUnsafeBufferPointer { click.observe($0, sampleRate: 16000) }
        XCTAssertFalse(click.hasActivity(sampleRate: 16000))
        let quiet = Array(repeating: Float(0.004), count: 3200)
        var speech = AudioActivity()
        quiet.withUnsafeBufferPointer { speech.observe($0, sampleRate: 16000) }
        XCTAssertTrue(speech.hasActivity(sampleRate: 16000))
    }
    func testRepeatDetectionFlagsBackToBackPhrasesOnly() {
        XCTAssertTrue(DictationText.repeatsItself("Send it now. Send it now."))
        XCTAssertFalse(DictationText.repeatsItself("I think that I think about it."))
    }
}
