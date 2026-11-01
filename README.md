# Yapp
Native macOS English dictation, powered by Whisper base.en and WhisperKit. No account or runtime downloads.

## Build
Open Package.swift in Xcode to edit. Run `./build.sh`, then `open build/Yapp.app` to use the microphone-enabled app bundle. Run the app bundle, not `swift run`.

Model assets and tokenizer are bundled from Models/. Build dependencies and models require internet during development; the assembled app uses local paths. First use may take longer while Core ML prepares the model.

Record, speak, stop, then copy the transcript. Each recording replaces the previous transcript. Temporary audio is deleted after transcription. No transcript history is persisted. Global shortcuts and automatic insertion are future work.

Third-party code: Vendor/WhisperKit (MIT; see its LICENSE and NOTICES). Model: OpenAI Whisper base.en, MIT. Tokenizer: openai/whisper-base.en. Preserve upstream notices when distributing.

Build and launch: `./script/build_and_run.sh`. Launch verification: `./script/build_and_run.sh --verify`.

Yapp vendor modification: ModelUtilities.loadTokenizer throws on local tokenizer failure rather than downloading a fallback.

To restore model assets: `python3 script/download_model.py` (development-only download).
