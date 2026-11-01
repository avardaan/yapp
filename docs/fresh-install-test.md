# Fresh-install test on this Mac

Use when asked to wipe Yapp and reinstall the latest DMG. This is a test reset,
not removal of the project. Do not run merely because this document is read.

1. **Prepare latest release first.** From the repo, run
   `./script/release.sh --notarize` using the existing `yapp-notary` Keychain
   profile. Require both notarization results to be Accepted, stapler validation,
   and Gatekeeper acceptance. Check the DMG checksum and source revision; an old
   DMG is not automatically the latest code. Do this before removing the old app.
2. **Quit every Yapp process**, including development and translocated copies.
   Verify none remain before changing state.
3. **Restore Globe behavior before deleting preferences.** Read
   `com.zeroslop.yapp`: if `globeActionConfigured` is true, restore
   `originalGlobeAction` into `com.apple.HIToolbox AppleFnUsageType`; if the saved
   key is absent, remove AppleFnUsageType. Never assume the original value was 0.
4. **Reset only Yapp permissions**, using `tccutil reset SERVICE com.zeroslop.yapp`
   for Microphone, Accessibility, and ListenEvent. Never reset all apps or edit
   the TCC database. Report any failed reset before proceeding.
5. **Clear Yapp state:** delete its defaults domain and exact app-specific cache
   `~/Library/Caches/com.zeroslop.yapp`. Inspect other Yapp-specific support,
   saved-state, and temporary `yapp-*.wav` paths before removing any leftovers.
   Do not sweep unrelated caches or all Core ML caches.
6. **Replace the installed app.** Verify the old app's bundle ID before removing
   `/Applications/Yapp.app` (and inspect `~/Applications/Yapp.app` if present).
   Mount the verified DMG read-only; verify Yapp.app and the Applications alias.
   Copy its app to `/Applications/Yapp.app`, never run the app from the DMG.
7. **Simulate a download.** Apply `com.apple.quarantine` to the installed test
   copy, then verify its signature, stapled ticket, and Gatekeeper assessment.
   Eject the DMG and open the installed bundle. Do not remove quarantine or
   bypass warnings to make the test pass. Check the actual running path; report
   App Translocation if macOS uses it.
8. **User verifies prompts and dictation.** Expect Microphone at launch followed
   by Accessibility setup; no Input Monitoring or Full Disk Access requirement.
   Grant permissions through normal macOS UI. Focus a text box, hold Fn, speak,
   release: check indicator, sounds, insertion, silence rejection, and a second
   recording. Test offline with networking disabled by the user or otherwise
   explicitly isolated; do not claim offline verification from model loading alone.

Preserve the repo, Models/, source/build dependencies, signing certificates and
private keys, `.signing-identity`, and `yapp-notary` credentials. Never rebuild or
launch the development copy during this release test. This resets user-specific
state; a separate macOS account remains the stronger clean-install test because
system-managed caches and OS history may survive. Record what was actually tested.
