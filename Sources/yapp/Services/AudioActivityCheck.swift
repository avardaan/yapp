import AVFoundation

enum AudioActivityCheck {
    static func hasActivity(at url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return false }
        var activity = AudioActivity()
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            activity.observe(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), sampleRate: file.processingFormat.sampleRate)
            if activity.hasActivity(sampleRate: file.processingFormat.sampleRate) { return true }
        }
        return false
    }
}
