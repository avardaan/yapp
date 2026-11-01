# Yapp: runtime architecture and platform requirements

Architecture snapshot: 2026-11-01. This is a guide for agents making changes,
not a changelog or a duplicate of source code. Update it when a runtime boundary,
platform requirement, or product constraint changes. Keep tunable values,
implementation details, command recipes, and benchmark results elsewhere.

## Product contract

- Yapp is a native macOS push-to-talk dictation utility from **zeroslop**. Keep
  the company name lowercase.
- It lives in the menu bar, without a Dock icon or main application window.
  A small, non-interactive activity indicator appears only during dictation;
  a standard About dialog is an intentional exception.
- Keep the experience quiet: preserve input focus, avoid extra windows, and use
  brief sound cues and restrained visual feedback. No custom onboarding flow
  is currently intended; use normal macOS permission prompts and Settings.
- Dictation must work entirely offline, including first launch after installation.
  Do not introduce accounts, cloud inference, runtime asset downloads, or telemetry
  transmission as incidental dependencies.

## Runtime flow

```text
App launch -> initialize local model and shortcut listener -> ready
Shortcut held -> capture original input target -> record microphone audio
Shortcut released -> stop capture -> check audio activity -> local ASR
  -> remove non-speech annotations -> validate original target -> paste text
  -> clean up temporary audio -> ready
```

Silence, cancellation, permission denial, and failures must not insert text.
Treat recording and transcription as separate phases. Prevent overlapping
sessions and reject late permission callbacks from cancelled recordings.

## Responsibilities and framework choices

- **App lifecycle and presentation:** SwiftUI owns the menu and observable UI;
  narrow AppKit bridges handle application lifecycle, the nonactivating activity
  panel, the native About dialog, and system integration. Preserve accessory
  activation behavior. The indicator must not take focus or intercept clicks.
- **Shortcut listener:** AppKit global and local event monitors observe the
  selected physical modifier and its release. Global and local events cover
  different destinations; avoid duplicate handling. Chords cancel dictation.
  Recover from permission changes or lost release events without leaving the
  microphone running. Persist the selected shortcut locally.
- **Dictation session:** owns lifecycle state, microphone capture, model lifetime,
  transcript processing, and cleanup. UI-facing state is main-actor-owned;
  isolate blocking work and avoid doing inference in keyboard callbacks.
- **Audio capture:** AVFoundation records temporary mono PCM audio suitable for
  ASR and provides levels for the indicator. Capture runs only during dictation.
- **Recognition:** WhisperKit runs bundled Core ML model components and a local
  tokenizer. The current baseline is OpenAI Whisper `base.en`, English-only.
  This is a Yapp asset, not a model supplied by macOS or an OpenAI API call.
  The model is loaded at launch and retained for responsive subsequent sessions.
- **Audio/text filtering:** a conservative audio-energy check rejects near-silence;
  this is not a learned voice-activity detector. Filter known non-speech decoder
  annotations before insertion while preserving legitimate speech.
- **Insertion:** Accessibility identifies the original focused input. Insert only
  if the same app and element remain focused; exclude secure text fields. Use
  the normal Paste path: some editors acknowledge Accessibility text writes
  without accepting visible input. Preserve clipboard types and restore them
  only if the clipboard has not changed meanwhile. Never restore focus or paste
  into a different field merely to force an insertion to succeed.

## Permissions and app identity

- The normal runtime requires **Microphone** for capture and **Accessibility**
  for shortcut observation, input-target checks, and insertion.
- The default listener does not request a separate Input Monitoring approval.
  On the development Mac, real Fn recording and insertion were verified after
  resetting that approval and confirming Yapp was absent from its Settings list.
  This is not yet proof for every supported macOS version or a clean install.
- The older Input Monitoring/event-tap backend remains available for diagnostic
  comparison, not as an automatic fallback that silently adds a permission.
- Do not add Screen Recording, Full Disk Access, Automation, or Apple's Speech
  Recognition permission for the existing dictation flow.
- Let macOS mediate approvals. A successful API registration or a visible Settings
  switch alone does not prove events or insertion work; verify real behavior.
- Keep bundle ID **`com.zeroslop.yapp`**, signer requirements, and application
  location consistent. Permission approvals depend on application identity.
  Changing identity may require fresh approvals.
- Local builds use an Apple Development certificate with its private key in
  Keychain. Never fall back silently to ad-hoc signing: it ties identity to an
  executable hash and previously broke approvals after rebuilds.
- Public direct distribution is a separate signing configuration: Developer ID
  Application, Hardened Runtime, secure timestamping, notarization, and stapling.
  Local development signing is not a public-release substitute.

## Local data and system settings

- Bundle every required model/tokenizer asset. Missing or corrupt assets must
  produce a local error rather than triggering a download. Preserve the vendored
  WhisperKit change that removes its tokenizer download fallback.
- Keep production transcripts in memory; no persistent transcript history is
  currently intended. Delete temporary audio on completion, cancellation, errors,
  and orderly shutdown. Do not equate normal cleanup with guaranteed crash cleanup
  or forensic erasure. Explicit diagnostic modes may have different output rules.
- Log lifecycle and permission diagnostics, not speech, typed text, clipboard
  contents, credentials, or private keys.
- When Fn is selected, preserve the user's previous Globe-key action before
  disabling its single-press emoji action. Restore that saved action automatically
  when selecting a different shortcut. Do not overwrite unrelated keyboard settings.

## Evolution and standing constraints

- Evaluate new models against the current baseline instead of assuming parameter
  count predicts quality, speed, memory, or battery cost. **yapp-bench** is a future
  direction for reproducible yappability measurements, not an implemented component.
- Distinguish model size, process RSS, physical footprint, accelerator allocations,
  and peak inference memory. Do not present one as another.
- Preserve third-party model/code licenses and attribution when changing engines.
- Make local commits at meaningful, checked checkpoints on `main`; split independent
  changes logically. Do not push without an explicit user request.
- Never commit secrets, private keys, local signing configuration, downloaded
  model assets, or build output.
