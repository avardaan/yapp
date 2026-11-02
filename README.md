# Yapp

Less clacking. More yapping.

Free, offline, on-device English dictation for macOS. Hold Fn, speak, then release
to insert text where you are writing. Yapp lives in the menu bar, with a small
sound-reactive indicator while recording. By **zeroslop**.

[Website](https://yapp.now/) · [Downloads](https://github.com/avardaan/yapp/releases/latest)

## Requirements

- Apple silicon Mac, macOS 14 or later for the official download.
- Microphone and Accessibility permission. The default shortcut listener does
  not request Input Monitoring. Right Option and Right Control are alternatives.
- No account, cloud transcription, or internet connection needed to dictate.

WhisperKit/Core ML runs a bundled Whisper `base.en` model. Yapp keeps no persistent
transcript history and deletes temporary recordings after completion or cancellation.
Insertion requires the original input to remain focused; secure fields are excluded.
Background noise can still cause recognition errors.

## Build from source

Install Xcode 16.4 or newer (Swift 6), Python 3, and an Apple code-signing
certificate. Clone this repository, then run:

```sh
python3 script/download_model.py
security find-identity -v -p codesigning
export YAPP_SIGNING_IDENTITY="YOUR CERTIFICATE NAME OR FINGERPRINT"
./build.sh
open build/Yapp.app
```

Internet is needed to fetch build dependencies and model assets; the assembled app
uses bundled local assets only. Run the app bundle rather than `swift run`, so macOS
can apply its microphone usage description and permissions identity correctly.
Keep your own signing identity and app location stable between builds. A change in
signing identity may require granting permissions again. Private keys stay in Keychain.

`swift test` runs the tests. `./script/build_and_run.sh` builds and launches the app.
The vendored WhisperKit tokenizer loader has a local-only modification: missing
local tokenizer files throw an error instead of downloading a fallback.

Fn setup saves the previous Globe-key action before disabling the emoji action;
selecting another shortcut restores the saved preference. Live keyboard preference
refresh varies by macOS version. Yapp never logs speech, clipboard contents, or typed text.

## Updates

Check for Updates… opens Sparkle’s native check, download, install, and relaunch
interface. Checks are manual only: no launch-time or scheduled requests, background
downloads, automatic installs, or system profiling. Dictation remains fully offline.
Update checks and downloads require internet, only when requested by the user.

The HTTPS feed is `https://yapp.now/appcast.xml`; archives live on GitHub Releases.
Sparkle verifies Ed25519 archive signatures before extraction and installation.
Version 0.1.1 and earlier need one manual installation of a version with the updater.
See [the update publishing guide](docs/updates.md).

## Releases and website

Use `YAPP_RELEASE_IDENTITY="YOUR DEVELOPER ID APPLICATION CERTIFICATE"` with
`./script/release.sh --build` to create a signed, unnotarized DMG for inspection.
For public distribution, store your own notarization credentials interactively with
`xcrun notarytool store-credentials yapp-notary`, then run:

```sh
export YAPP_RELEASE_IDENTITY="YOUR DEVELOPER ID APPLICATION CERTIFICATE"
./script/release.sh --notarize
```

This notarizes and staples the app and DMG, verifies signatures and Gatekeeper,
and writes a SHA-256 checksum under `build/distribution/`. Signing credentials,
models, and build output are excluded from Git. Publish DMGs as GitHub Release
assets, not repository files. A release must include corresponding source under
the GPL, including changes used to build it. Keep the release tag at that source commit.

The public site is deployed from `website/` through GitHub Actions. Only that
folder is uploaded to Pages. See [website/README.md](website/README.md).

## License

Yapp’s original code is **GPL-3.0-only**. Copyright © 2026 zeroslop.
See [LICENSE](LICENSE) and [BRANDING.md](BRANDING.md).

Sparkle 2.10.1 is BSD licensed with additional upstream notices; its full LICENSE
is bundled with the app.

WhisperKit is MIT licensed; preserve `Vendor/WhisperKit/LICENSE` and `NOTICES`.
Whisper model weights and tokenizer originate from OpenAI Whisper (MIT); the
model conversion is obtained from Argmax’s WhisperKit Core ML repository.
See `Resources/Licenses/Whisper-LICENSE`. These upstream licenses remain in force.
