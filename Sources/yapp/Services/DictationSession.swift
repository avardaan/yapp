import AppKit
import AVFoundation
import WhisperKit
import OSLog

@MainActor
final class DictationSession: ObservableObject {
    static let shared = DictationSession()
    enum Phase { case loading, ready, requestingPermission, recording, transcribing, failed }
    private var nextDictation = 0
    private var activeDictation: Int?
    private var dictationStarted: TimeInterval = 0
    private var captureStarted: TimeInterval?
    private var captureMS: Double = 0
    private var processingStarted: TimeInterval?
    @Published var phase: Phase = .loading {
        didSet { if oldValue != phase { Diagnostics.shared.record("phase.changed", category: "Dictation", dictation: activeDictation, fields: ["phase": String(describing: phase)]) } }
    }
    @Published var status = "Loading English model…"
    @Published var transcript = ""
    @Published var inputLevel: Double = 0
    @Published private(set) var waitingForModel = false
    private var meterTimer: Timer?
    private var engine: WhisperKit?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var initialized = false
    private var permissionRequest = UUID()
    @Published private(set) var shortcutOwnsRecording = false
    private var pendingShortcut: Task<Void, Never>?
    private var insertionTarget: TextInsertion.Target?
    private var tutorialID: UUID?

    func shortcutPressed() {
        guard (phase == .ready || phase == .loading), !shortcutOwnsRecording else {
            Diagnostics.shared.record("shortcut.ignored", category: "Shortcut", fields: ["reason": shortcutOwnsRecording ? "already_held" : String(describing: phase)])
            return
        }
        nextDictation += 1
        activeDictation = nextDictation
        dictationStarted = ProcessInfo.processInfo.systemUptime
        captureMS = 0; captureStarted = nil; processingStarted = nil
        trace("dictation.started")
        shortcutOwnsRecording = true
        tutorialID = FirstLaunchGuide.shared.practiceID
        insertionTarget = tutorialID == nil ? TextInsertion.captureTarget() : nil
        if phase == .loading {
            waitingForModel = true
            trace("dictation.waiting_for_model")
            return
        }
        scheduleShortcutStart()
    }

    private func scheduleShortcutStart() {
        // Keep capture out of keyboard callbacks and allow a release to cancel startup.
        pendingShortcut = Task { [weak self] in
            guard !Task.isCancelled else { return }
            guard let self, self.shortcutOwnsRecording, self.phase == .ready else { return }
            self.start()
            self.waitingForModel = false
        }
    }

    func shortcutReleased() {
        guard shortcutOwnsRecording else { return }
        pendingShortcut?.cancel(); pendingShortcut = nil
        shortcutOwnsRecording = false
        waitingForModel = false
        if phase == .requestingPermission { cancelRecording() }
        else if phase == .recording { Task { await stop() } }
        else { finish("cancelled_before_capture") }
    }

    func cancelShortcut() {
        guard shortcutOwnsRecording else { return }
        pendingShortcut?.cancel(); pendingShortcut = nil
        shortcutOwnsRecording = false
        waitingForModel = false
        cancelRecording()
    }

    func prepare() async {
        guard !initialized else { return }
        initialized = true
        let loadStarted = ProcessInfo.processInfo.systemUptime
        Diagnostics.shared.record("model.loading", category: "Model")
        do {
            let model = Bundle.main.resourceURL!.appendingPathComponent("Models")
            for name in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc", "tokenizer.json", "tokenizer_config.json"] {
                guard FileManager.default.fileExists(atPath: model.appendingPathComponent(name).path) else {
                    throw NSError(domain: "yapp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bundled model asset: \(name). Run the build script again."])
                }
            }
            engine = try await WhisperKit(WhisperKitConfig(modelFolder: model.path, tokenizerFolder: model, verbose: false, download: false))
            Diagnostics.shared.record("model.ready", category: "Model", fields: ["duration_ms": String(Diagnostics.milliseconds(since: loadStarted))])
            if let timings = engine?.currentTimings {
                Diagnostics.shared.record("model.stages", category: "Model", fields: [
                    "encoder_ms": String((timings.encoderLoadTime * 1000).rounded()),
                    "decoder_ms": String((timings.decoderLoadTime * 1000).rounded()),
                    "tokenizer_ms": String((timings.tokenizerLoadTime * 1000).rounded())
                ])
            }
            modelBecameReady()
            if let index = CommandLine.arguments.firstIndex(of: "--smoke-audio"), CommandLine.arguments.count > index + 1 {
                let results = try await engine!.transcribe(audioPath: CommandLine.arguments[index + 1], decodeOptions: DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true))
                let text = results.map(\.text).joined(separator: " ")
                try text.write(toFile: "/tmp/yapp-smoke-result.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        } catch {
            Diagnostics.shared.record("model.failed", category: "Model", severity: .error, fields: ["duration_ms": String(Diagnostics.milliseconds(since: loadStarted)), "error_code": String((error as NSError).code)])
            fail(error)
        }
    }

    /// A pending hold may continue only while it is still owned by the shortcut.
    func modelBecameReady() {
        phase = .ready
        status = "Ready · English · On-device"
        if waitingForModel && shortcutOwnsRecording { scheduleShortcutStart() }
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
                    self.finish("microphone_denied", severity: .error)
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
            guard capture.record() else { throw NSError(domain: "yapp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start the microphone."]) }
            recorder = capture
            captureStarted = ProcessInfo.processInfo.systemUptime
            trace("capture.started")
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
        } catch {
            finish("capture_failed", severity: .error, error: error)
            cleanup(); phase = .ready; status = error.localizedDescription
        }
    }

    func stop() async {
        guard phase == .recording, let url = audioURL, let engine else { return }
        meterTimer?.invalidate(); meterTimer = nil; inputLevel = 0
        recorder?.stop()
        recorder = nil
        if let captureStarted { captureMS = Diagnostics.milliseconds(since: captureStarted) }
        captureStarted = nil
        trace("capture.stopped")
        processingStarted = ProcessInfo.processInfo.systemUptime
        phase = .transcribing
        status = "Transcribing on your Mac…"
        defer { cleanup() }
        do {
            let hasActivity = try await Task.detached(priority: .userInitiated) {
                try AudioActivityCheck.hasActivity(at: url)
            }.value
            guard hasActivity else {
                finish("silence_rejected")
                transcript = ""
                phase = .ready
                status = "No speech detected"
                return
            }
            let options = DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true)
            trace("transcription.started")
            let transcriptionStarted = ProcessInfo.processInfo.systemUptime
            let results = try await engine.transcribe(audioPath: url.path, decodeOptions: options)
            trace("transcription.completed", fields: ["duration_ms": String(Diagnostics.milliseconds(since: transcriptionStarted))])
            transcript = DictationText.clean(results.map(\.text).joined(separator: " "))
            guard !transcript.isEmpty else {
                finish("empty_or_annotation_rejected")
                phase = .ready
                status = "No speech detected"
                return
            }
            if let tutorialID {
                let delivered = FirstLaunchGuide.shared.receivePracticeText(transcript, for: tutorialID)
                finish(delivered ? "tutorial_displayed" : "tutorial_closed")
                transcript = ""
                phase = .ready
                status = "Ready · English · On-device"
                return
            }
            trace("insertion.started")
            let insertionStatus = await TextInsertion.insert(transcript, into: insertionTarget, dictation: activeDictation)
            finish(insertionStatus == nil ? "paste_sent" : "insertion_skipped")
            phase = .ready
            status = insertionStatus ?? "Ready · English · On-device"
        } catch {
            finish("processing_failed", severity: .error, error: error)
            phase = .ready; status = error.localizedDescription
        }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
    func cancelRecording() {
        guard phase == .recording || phase == .requestingPermission else {
            finish("cancelled_before_capture"); return
        }
        if let captureStarted { captureMS = Diagnostics.milliseconds(since: captureStarted) }
        finish("cancelled")
        permissionRequest = UUID()
        cleanup()
        phase = .ready
        status = "Recording discarded"
    }

    func cancelTutorial(id: UUID) {
        guard tutorialID == id else { return }
        // Processing can finish locally, but its invalidated tutorial token prevents delivery.
        if phase != .transcribing { cancelShortcut() }
        transcript = ""
    }

    func retryLoading() {
        guard phase == .failed else { return }
        initialized = false
        phase = .loading
        status = "Loading English model…"
        Task { await prepare() }
    }

    func shutdown() {
        pendingShortcut?.cancel()
        waitingForModel = false
        shortcutOwnsRecording = false
        if let captureStarted { captureMS = Diagnostics.milliseconds(since: captureStarted) }
        finish("app_terminated")
        cleanup()
        if engine != nil {
            engine = nil
            Diagnostics.shared.record("model.reference_released", category: "Model")
        }
    }

    private func trace(_ event: String, fields: [String: String] = [:]) {
        Diagnostics.shared.record(event, category: "Dictation", dictation: activeDictation, fields: fields)
    }

    private func finish(_ outcome: String, severity: Diagnostics.Severity = .normal, error: Error? = nil) {
        guard let id = activeDictation else { return }
        var fields = ["outcome": outcome,
                      "duration_ms": String(Diagnostics.milliseconds(since: dictationStarted)),
                      "capture_ms": String(captureMS)]
        if let processingStarted { fields["processing_ms"] = String(Diagnostics.milliseconds(since: processingStarted)) }
        if let error { fields["error_code"] = String((error as NSError).code) }
        Diagnostics.shared.record("dictation.completed", category: "Dictation", dictation: id, severity: severity, fields: fields)
        activeDictation = nil
    }

    private func cleanup() {
        meterTimer?.invalidate(); meterTimer = nil; inputLevel = 0
        recorder?.stop(); recorder = nil
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        insertionTarget = nil
        tutorialID = nil
    }
    private func fail(_ error: Error) {
        waitingForModel = false
        shortcutOwnsRecording = false
        finish("model_failed", severity: .error, error: error)
        phase = .failed; status = error.localizedDescription
    }
}
