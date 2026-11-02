# Manual app updates

Sparkle 2.10.1 provides the standard macOS update UI. The updater is lazy: the
menu action creates it, enforces manual-only settings, and initiates the check.
The delegate rejects background and informational checks as a second guard.
The menu is unavailable while recording/transcribing or during another check.
No update network requests are needed for normal dictation or app launch.

## Identity and verification

- Feed: https://yapp.now/appcast.xml (GitHub Pages, `website/appcast.xml`).
- Archives: versioned GitHub Release ZIPs containing the stapled `Yapp.app`.
- `SUPublicEDKey` contains the public Ed25519 key. The private key is a Sparkle
  item in login Keychain, account `zeroslop.yapp`; never export it into the repo.
- Developer ID signs the framework, helpers, and application inside-out. Sparkle
  additionally verifies the archive’s Ed25519 signature before extraction.
- `CFBundleVersion` is the increasing build number Sparkle compares;
  `CFBundleShortVersionString` is the human-readable release version.
- Keep bundle ID, Developer ID team, and update key stable. Key rotation requires
  a planned migration, not replacing the public key in a release arbitrarily.

## Publishing

1. Increase both version and build number in Info.plist; add release notes under
   `docs/releases/<version>.md`. Commit and tag the exact source used for the app.
2. Set `YAPP_RELEASE_IDENTITY` and run `./script/release.sh --notarize`.
   SwiftPM resolves the pinned Sparkle distribution. The script embeds framework
   symlinks intact, signs helpers/framework/app inside-out, notarizes and staples
   app and DMG, and checks Gatekeeper. It creates a fresh update ZIP after stapling.
3. `script/generate-appcast.sh` uses Sparkle’s official tool and the Keychain key
   to sign `build/distribution/updates/Yapp-<version>-arm64.zip` and generate its
   appcast. It checks the public key matches Info.plist, preserves earlier feed
   entries, and disables delta generation. It does not publish anything.
4. Upload the DMG, checksum, and update ZIP to the matching GitHub Release first.
   Confirm the public download URL and digest. Then copy the generated appcast
   into `website/appcast.xml`, update the site’s DMG link, commit and push Pages.
   Never advertise an archive before it is available.
5. Test an older, signed updater-enabled build against the live feed: manually
   check, download, install/relaunch, then verify the installed build/signature.
   Also verify current-version, offline/error, cancellation, and invalid-signature
   behavior. Source version 0.1.1 has no updater and must be upgraded manually once.

Sparkle’s tools are in `.build/artifacts/sparkle/Sparkle/bin/` after package
resolution. To generate the key on a new publisher machine, use
`generate_keys --account zeroslop.yapp`; back up the Keychain securely outside Git.
For an existing app, restore the existing key rather than generating a new one.
