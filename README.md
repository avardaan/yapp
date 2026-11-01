# Yapp
Native macOS English dictation, powered by Whisper base.en and WhisperKit. No account or runtime downloads.

## Build
Open Package.swift in Xcode to edit. Run `./build.sh`, then `open build/Yapp.app` to use the microphone-enabled app bundle. Run the app bundle, not `swift run`.

Model assets and tokenizer are bundled from Models/. Build dependencies and models require internet during development; the assembled app uses local paths. First use may take longer while Core ML prepares the model.

Yapp intentionally runs only in the menu bar (LSUIElement/accessory), with no Dock icon, main window, or separate settings window. A small non-interactive Pac-Man-inspired indicator appears near the bottom of the cursor’s display only while recording/transcribing. It shows live microphone levels or processing dots; quiet local sound cues mark recording and transcription start. It respects Reduce Motion and never takes keyboard focus. The model loads at launch. Hold Fn to record and release to transcribe and insert. The top-level menu contains only About, Status, Shortcut, Permissions, and Quit. Recording and transcription have distinct menu bar symbols. Discard Recording deletes unfinished audio. Permissions and status details are available within the menu. Each recording replaces the previous transcript. Temporary audio is deleted after transcription. No transcript history is persisted. Hold the bottom-left Fn/Globe key to record; release to transcribe. Global shortcut access requires Input Monitoring (enable Yapp and restart it if macOS asks). Text insertion requires Accessibility permission. Yapp captures the input field at recording start and inserts only if the same field remains focused. It sends the normal system Paste command and restores the clipboard unless it changed meanwhile; it avoids AXSelectedText writes because some editors silently ignore them. Secure fields are excluded. Copy Last Transcript remains available if insertion is unavailable. Fn chords discard dictation. Very quick taps (<120 ms) are ignored, and a lost release or hold beyond 2 minutes discards recording.

Third-party code: Vendor/WhisperKit (MIT; see its LICENSE and NOTICES). Model: OpenAI Whisper base.en, MIT. Tokenizer: openai/whisper-base.en. Preserve upstream notices when distributing.

Build and launch: `./script/build_and_run.sh`. Launch verification: `./script/build_and_run.sh --verify`.

Yapp vendor modification: ModelUtilities.loadTokenizer throws on local tokenizer failure rather than downloading a fallback.

To restore model assets: `python3 script/download_model.py` (development-only download).

On first launch, Yapp saves the existing `com.apple.HIToolbox AppleFnUsageType` setting and sets it to 0 (single-press Globe does nothing) to avoid the emoji picker conflict. This is a per-user macOS setting and persists when Yapp quits. Changing the shortcut away from Fn automatically restores the saved Globe action, including the original unset state. No custom installer exists yet; this setup runs on first launch. Input monitoring observes Fn state and chords only; it does not record typed text.

Debugging: `log show --last 5m --style compact --predicate 'subsystem == "com.zeroslop.yapp"'` reports listener state, Fn transitions, and dictation phases without transcript contents. Builds use the Apple Development identity configured by the public certificate fingerprint in the ignored .signing-identity file (or YAPP_SIGNING_IDENTITY). No ad-hoc fallback is used. Keep the bundle ID, signing team, and app location stable. The first transition from ad-hoc signing or a different bundle ID requires new Input Monitoring, Accessibility, and microphone approvals.

Bundle ID: `com.zeroslop.yapp` (zeroslop). Certificate configuration: `security find-identity -v -p codesigning`; put the chosen public identity fingerprint into `.signing-identity`, or export `YAPP_SIGNING_IDENTITY`. Private keys must stay in Keychain and must never be committed. Local development builds disable network timestamping; public distribution signing/notarization is a separate workflow.

Shortcut menu: current key and Change Shortcut… only. Fixed choices are Fn, Right Option, and Right Control, all push-to-talk. Input Monitoring controls live in Permissions; menu items remain static regardless of setup state. Listener recovery is automatic.
