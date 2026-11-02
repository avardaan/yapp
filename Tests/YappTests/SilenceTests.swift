import XCTest
import AppKit
@testable import Yapp

final class SilenceTests: XCTestCase {
    func testNonSpeechAnnotationsProduceNoText() {
        for text in ["[Silence]", " (silence) ", "[BLANK_AUDIO]", "[Silence] [Silence]", "[music]", "(footsteps)", "{Paused]", "[Paused]", "(mouse clicking)", "[keyboard typing]", "(clicking)"] {
            XCTAssertEqual(DictationText.clean(text), "")
        }
    }
    func testRealSpeechAndUnrelatedBracketsRemain() {
        XCTAssertEqual(DictationText.clean("I prefer silence."), "I prefer silence.")
        XCTAssertEqual(DictationText.clean("I paused before clicking the mouse."), "I paused before clicking the mouse.")
        XCTAssertEqual(DictationText.clean("Hello. (mouse clicking) Next sentence."), "Hello. Next sentence.")
        XCTAssertEqual(DictationText.clean("[Silence] Hello there."), "Hello there.")
        XCTAssertEqual(DictationText.clean("Review [architecture] tomorrow."), "Review [architecture] tomorrow.")
    }
    func testSilentAudioAndBriefClickHaveNoActivity() {
        var samples = Array(repeating: Float(0), count: 16000)
        var silence = AudioActivity()
        samples.withUnsafeBufferPointer { silence.observe($0, sampleRate: 16000) }
        XCTAssertFalse(silence.hasActivity(sampleRate: 16000))
        samples[500] = 1
        var click = AudioActivity()
        samples.withUnsafeBufferPointer { click.observe($0, sampleRate: 16000) }
        XCTAssertFalse(click.hasActivity(sampleRate: 16000))
    }
    func testQuietSustainedAudioRemainsEligible() {
        let samples = Array(repeating: Float(0.004), count: 3200)
        var audio = AudioActivity()
        samples.withUnsafeBufferPointer { audio.observe($0, sampleRate: 16000) }
        XCTAssertTrue(audio.hasActivity(sampleRate: 16000))
    }
    @MainActor
    func testSilenceAnnotationCannotReachInputOrClipboard() async {
        let revision = NSPasteboard.general.changeCount
        let result = await TextInsertion.insert("[Silence]", into: nil)
        XCTAssertEqual(result, "No speech detected")
        XCTAssertEqual(NSPasteboard.general.changeCount, revision)
    }
}
