# Yapp

Runtime snapshot: 2026-11-01. Keep this guide concise; update it when architectural
choices or requirements change, not for routine implementation changes.

## Runtime architecture

- Native macOS menu-bar app: SwiftUI UI with small AppKit bridges. No Dock icon
  or main window; a nonactivating activity bar and standard About dialog are allowed.
- Flow: hold shortcut → capture focused input → record audio → release → reject
  near-silence → transcribe locally → filter non-speech labels → validate focus
  → paste → delete temporary audio.
- AppKit global/local event monitors detect shortcuts using Accessibility access.
  The old Input Monitoring backend is diagnostic-only; no automatic fallback.
- A main-actor-owned dictation session coordinates state and cleanup. Keep
  recording/inference out of keyboard callbacks and prevent overlapping sessions.
- AVFoundation captures microphone audio. WhisperKit/Core ML runs bundled Whisper
  `base.en` and its tokenizer, loaded at launch. The model is not supplied by macOS.

## Requirements and constraints

- **Offline:** bundle all inference assets. Missing assets fail locally; never
  silently download models or fall back to cloud services.
- **Permissions:** Microphone and Accessibility only for the normal flow. No custom
  onboarding screens. Request Microphone at first launch, then Accessibility; never
  start recording merely because permission was granted. The Accessibility-only listener is verified on the development
  Mac; clean-install and supported-macOS testing remain release requirements.
- **Safe insertion:** use normal Paste only into the original, still-focused,
  non-secure input. Restore the clipboard only if it has not changed meanwhile.
- **Session safety:** silence, cancellation, and errors insert nothing. Ignore stale
  permission callbacks; recover from lost key releases without leaving capture active.
- **Privacy:** no persistent transcript history. Clean up temporary audio on normal
  completion, cancellation, failure, and shutdown. Never log speech, typed text,
  clipboard contents, or secrets. Crash cleanup is not guaranteed.
- **System settings:** save Fn's previous Globe action before disabling it; restore
  it when the user selects another shortcut. Preserve unrelated settings.
- **Identity:** keep `com.zeroslop.yapp`, signing requirements, and app location
  stable. Use certificate-based signing; no silent ad-hoc fallback. Private keys
  stay in Keychain. Public downloads need a separate Developer ID/notarization setup.
- **Product:** company name is always **zeroslop**. Keep the UI quiet and preserve
  input focus. Preserve third-party licenses and attribution.
- **Changes:** make meaningful local commits on `main`; do not push without being
  asked. Never commit secrets, signing configuration, models, or build output.
- **Models:** benchmark replacements rather than guessing from parameter counts.
  Distinguish download size, process memory, accelerator allocations, and peak use.
  `yapp-bench` is a future direction, not an existing subsystem.
