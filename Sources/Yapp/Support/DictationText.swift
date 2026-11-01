import Foundation

/// Remove known non-speech annotations without removing ordinary spoken words.
enum DictationText {
    static func clean(_ text: String) -> String {
        let annotations = #"(?i)[\[(]\s*(?:silence|blank[ _]audio|no[ _]speech|inaudible|unintelligible|music|applause|laughter|footsteps|background noise)\s*[\])]"#
        return text.replacingOccurrences(of: annotations, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Conservative near-silence gate, not a speech classifier. Ordinary background
/// sound may pass; decoder annotation filtering handles that separately.
struct AudioActivity {
    private var activeFrames = 0
    private var totalFrames = 0
    mutating func observe(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        let window = max(1, Int(sampleRate * 0.02))
        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + window)
            var energy: Double = 0
            for index in offset..<end { energy += Double(samples[index]) * Double(samples[index]) }
            let rms = sqrt(energy / Double(end - offset))
            totalFrames += end - offset
            // -60 dBFS is deliberately low so quiet speech remains eligible.
            if rms > 0.001 { activeFrames += end - offset }
            offset = end
        }
    }
    func hasActivity(sampleRate: Double) -> Bool {
        totalFrames > 0 && Double(activeFrames) / sampleRate >= 0.12
    }
}
