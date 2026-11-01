import SwiftUI
import AVFoundation
import WhisperKit

@main
struct YappApp: App {
    @StateObject private var session = DictationSession()
    var body: some Scene {
        WindowGroup("Yapp") { ContentView(session: session) }
            .defaultSize(width: 560, height: 440)
        MenuBarExtra("Yapp", systemImage: "waveform") {
            Button("Show Yapp") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("Quit Yapp") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class DictationSession: ObservableObject {
    enum Phase { case loading, ready, requestingPermission, recording, transcribing, failed }
    @Published var phase: Phase = .loading
    @Published var status = "Loading English model…"
    @Published var transcript = ""
    private var engine: WhisperKit?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var initialized = false

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
        phase = .requestingPermission
        status = "Checking microphone access…"
        // Use the callback API directly: the SDK-generated async Bool bridge
        // crashed in CheckedContinuation.resume on this Mac after TCC replied.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
            guard capture.record() else { throw NSError(domain: "Yapp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start the microphone."]) }
            recorder = capture
            phase = .recording
            status = "Listening… Click Stop when you’re done."
        } catch { cleanup(); phase = .ready; status = error.localizedDescription }
    }

    func stop() async {
        guard phase == .recording, let url = audioURL, let engine else { return }
        recorder?.stop()
        recorder = nil
        phase = .transcribing
        status = "Transcribing on your Mac…"
        defer { cleanup() }
        do {
            let options = DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true)
            let results = try await engine.transcribe(audioPath: url.path, decodeOptions: options)
            transcript = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .ready
            status = transcript.isEmpty ? "No speech detected. Try again." : "Done · Audio deleted · Transcript stays here"
        } catch { phase = .ready; status = error.localizedDescription }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
    private func cleanup() {
        recorder?.stop(); recorder = nil
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
    }
    private func fail(_ error: Error) { phase = .failed; status = error.localizedDescription }
}

struct ContentView: View {
    @ObservedObject var session: DictationSession
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.system(size: 38)).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Yapp").font(.largeTitle.bold())
                    Text("Your voice. On your Mac.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(session.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            TextEditor(text: $session.transcript)
                .font(.system(size: 16)).padding(8)
                .background(.background).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            HStack {
                Button { Task { if session.phase == .recording { await session.stop() } else { session.start() } } } label: {
                    Label(session.phase == .recording ? "Stop & Transcribe" : "Record", systemImage: session.phase == .recording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent).tint(session.phase == .recording ? .red : .orange)
                .disabled(session.phase != .ready && session.phase != .recording)
                if session.phase == .loading || session.phase == .transcribing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Copy", action: session.copy).disabled(session.transcript.isEmpty)
            }
        }
        .padding(24).frame(minWidth: 480, minHeight: 380)
        .task { await session.prepare() }
    }
}
