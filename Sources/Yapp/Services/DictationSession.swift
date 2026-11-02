import AppKit
import AVFoundation
import WhisperKit
import OSLog

@MainActor
final class DictationSession: ObservableObject {
    static let shared = DictationSession()
    enum Phase { case loading, ready, requestingPermission, recording, transcribing, failed }
    private let logger = Logger(subsystem: "com.zeroslop.yapp", category: "Dictation")
    @Published var phase: Phase = .loading {
        didSet { if oldValue != phase { logger.info("Phase: \(String(describing: self.phase), privacy: .public)") } }
    }
    @Published var status = "Loading English model…"
    @Published var transcript = ""
    @Published var inputLevel: Double = 0
    private var meterTimer: Timer?
    private var engine: WhisperKit?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var initialized = false
    private var permissionRequest = UUID()
    private var shortcutOwnsRecording = false
    private var pendingShortcut: Task<Void, Never>?
    private var insertionTarget: TextInsertion.Target?

    func shortcutPressed() {
        guard phase == .ready, !shortcutOwnsRecording else { return }
        shortcutOwnsRecording = true
        insertionTarget = TextInsertion.captureTarget()
        // Start on key-down without a hold threshold; keep capture out of the keyboard callback.
        pendingShortcut = Task { [weak self] in
            guard !Task.isCancelled else { return }
            guard let self, self.shortcutOwnsRecording, self.phase == .ready else { return }
            self.start()
        }
    }

    func shortcutReleased() {
        guard shortcutOwnsRecording else { return }
        pendingShortcut?.cancel(); pendingShortcut = nil
        shortcutOwnsRecording = false
        if phase == .requestingPermission { cancelRecording() }
        else if phase == .recording { Task { await stop() } }
    }

    func cancelShortcut() {
        guard shortcutOwnsRecording else { return }
        pendingShortcut?.cancel(); pendingShortcut = nil
        shortcutOwnsRecording = false
        cancelRecording()
    }

    func prepare() async {
        guard !initialized else { return }
        initialized = true
        do {
            let model = Bundle.main.resourceURL!.appendingPathComponent("Models")
            for name in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc", "tokenizer.json", "tokenizer_config.json"] {
                guard FileManager.default.fileExists(atPath: model.appendingPathComponent(name).path) else {
                    throw NSError(domain: "Yapp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bundled model asset: \(name). Run the build script again."])
                }
            }
            engine = try await WhisperKit(WhisperKitConfig(modelFolder: model.path, tokenizerFolder: model, download: false))
            phase = .ready
            status = "Ready · English · On-device"
            if let index = CommandLine.arguments.firstIndex(of: "--smoke-audio"), CommandLine.arguments.count > index + 1 {
                let results = try await engine!.transcribe(audioPath: CommandLine.arguments[index + 1], decodeOptions: DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true))
                let text = results.map(\.text).joined(separator: " ")
                try text.write(toFile: "/tmp/yapp-smoke-result.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        } catch { fail(error) }
    }

    func start() {
        guard phase == .ready else { return }
        if !shortcutOwnsRecording { insertionTarget = TextInsertion.captureTarget() }
        permissionRequest = UUID()
        let request = permissionRequest
        phase = .requestingPermission
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            beginRecording()
            return
        }
        status = "Checking microphone access…"
        // Use the callback API directly: the SDK-generated async Bool bridge
        // crashed in CheckedContinuation.resume on this Mac after TCC replied.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .requestingPermission, self.permissionRequest == request else { return }
                guard granted else {
                    self.phase = .ready
                    self.status = "Allow microphone access in System Settings → Privacy & Security → Microphone."
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard phase == .requestingPermission else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("yapp-\(UUID().uuidString).wav")
            audioURL = url
            let capture = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            capture.isMeteringEnabled = true
            guard capture.record() else { throw NSError(domain: "Yapp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start the microphone."]) }
            recorder = capture
            meterTimer?.invalidate()
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    self.inputLevel = min(1, max(0, (Double(recorder.averagePower(forChannel: 0)) + 55) / 50))
                }
            }
            phase = .recording
            status = "Recording · Release shortcut to finish"
        } catch { cleanup(); phase = .ready; status = error.localizedDescription }
    }

    func stop() async {
        guard phase == .recording, let url = audioURL, let engine else { return }
        meterTimer?.invalidate(); meterTimer = nil; inputLevel = 0
        recorder?.stop()
        recorder = nil
        phase = .transcribing
        status = "Transcribing on your Mac…"
        defer { cleanup() }
        do {
            let hasActivity = try await Task.detached(priority: .userInitiated) {
                try AudioActivityCheck.hasActivity(at: url)
            }.value
            guard hasActivity else {
                transcript = ""
                phase = .ready
                status = "No speech detected"
                return
            }
            let options = DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true)
            let results = try await engine.transcribe(audioPath: url.path, decodeOptions: options)
            transcript = DictationText.clean(results.map(\.text).joined(separator: " "))
            guard !transcript.isEmpty else {
                phase = .ready
                status = "No speech detected"
                return
            }
            let insertionStatus = await TextInsertion.insert(transcript, into: insertionTarget)
            phase = .ready
            status = insertionStatus ?? "Ready · English · On-device"
        } catch { phase = .ready; status = error.localizedDescription }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
    func cancelRecording() {
        guard phase == .recording || phase == .requestingPermission else { return }
        permissionRequest = UUID()
        cleanup()
        phase = .ready
        status = "Recording discarded"
    }

    func retryLoading() {
        guard phase == .failed else { return }
        initialized = false
        phase = .loading
        status = "Loading English model…"
        Task { await prepare() }
    }

    func shutdown() { pendingShortcut?.cancel(); cleanup() }

    private func cleanup() {
        meterTimer?.invalidate(); meterTimer = nil; inputLevel = 0
        recorder?.stop(); recorder = nil
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        insertionTarget = nil
    }
    private func fail(_ error: Error) { phase = .failed; status = error.localizedDescription }
}
