# yapp

Runtime snapshot: 2026-11-01. Keep this guide concise; update it when architectural
choices or requirements change, not for routine implementation changes.

## Runtime architecture

- Native macOS menu-bar app: SwiftUI UI with small AppKit bridges. No Dock icon
  or main window; a nonactivating activity bar, About dialog, and on-demand diagnostic sharing dialog are allowed.
- Holding the shortcut during model loading shows an indeterminate preparation pill;
  continue into recording only if still held when ready. Early release cancels.
- Flow: hold shortcut → capture focused input → record audio → release → reject
  near-silence → transcribe locally → filter non-speech labels → validate focus
  → paste → delete temporary audio.
- AppKit global/local event monitors detect shortcuts using Accessibility access.
  The old Input Monitoring backend is diagnostic-only; no automatic fallback.
- A main-actor-owned dictation session coordinates state and cleanup. Keep
  recording/inference out of keyboard callbacks and prevent overlapping sessions.
- Updates: Sparkle 2 is initialized only by Check for Updates…; no scheduled checks,
  automatic downloads/installs, or profiling. HTTPS appcast is published by Pages;
  archives on GitHub Releases require Ed25519 signatures. Private key stays in Keychain.
- AVFoundation captures microphone audio. WhisperKit/Core ML runs bundled Whisper
  `base.en` and its tokenizer, loaded at launch. The model is not supplied by macOS.

## Requirements and constraints

- **Offline:** bundle all inference assets. Missing assets fail locally; never
  silently download models or fall back to cloud services.
- **Permissions:** Microphone and Accessibility only for the normal flow. A one-time nonactivating tutorial appears after permissions; an initial Preparing screen waits for model readiness before practice begins;
  it centers a transient practice box and explains the real activity pill. Shortcut holds dictate into that box until
  dismissed with Escape; show the close hint after the first successful result.
  Never paste practice text into another app. Request Microphone at first launch, then Accessibility; never
  start recording merely because permission was granted. The Accessibility-only listener is verified on the development
  Mac; clean-install and supported-macOS testing remain release requirements.
- **Safe insertion:** use normal Paste only into the original, still-focused,
  non-secure input. Restore the clipboard only if it has not changed meanwhile.
- **Session safety:** silence, cancellation, and errors insert nothing. Ignore stale
  permission callbacks; recover from lost key releases without leaving capture active.
- **Diagnostics:** One fixed local event stream, Apple unified logging, and a bounded current-launch JSONL export. No verbosity setting or remote uploads. Track each dictation from accepted press to one terminal outcome; release ends capture. Log timings and controlled metadata only. Disable dependency text/token logging.
- **Privacy:** no persistent transcript history. Clean up temporary audio on normal
  completion, cancellation, failure, and shutdown. Never log speech, typed text,
  clipboard contents, or secrets. Crash cleanup is not guaranteed.
- **System settings:** save Fn's previous Globe action before disabling it; restore
  it when the user selects another shortcut. Preserve unrelated settings.
- **Identity:** keep `com.zeroslop.yapp`, signing requirements, and app location
  stable. Use certificate-based signing; no silent ad-hoc fallback. Private keys
  stay in Keychain. Public downloads need a separate Developer ID/notarization setup.
- **Product:** user-facing creator credit is **Vardaan**, linked to `https://github.com/avardaan`. Keep internal bundle/signing identifiers unchanged. Keep the UI quiet and preserve
  input focus. Preserve third-party licenses and attribution.
- **Changes:** make meaningful local commits on `main`; publish only when requested; source, releases, and Pages share `avardaan/yapp`. Never commit secrets, signing configuration, models, or build output.
- **Models:** benchmark replacements rather than guessing from parameter counts.
  Distinguish download size, process memory, accelerator allocations, and peak use.
  `yapp-bench` is a future direction, not an existing subsystem.

For an authorized wipe/reinstall test, follow `docs/fresh-install-test.md`.
Preserve project assets and Keychain credentials; prepare the latest notarized DMG
before resetting state, and restore the saved Globe action before deleting defaults.
