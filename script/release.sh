#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:---build}"
[[ "$MODE" == --build || "$MODE" == --notarize ]] || { echo "Usage: $0 [--build|--notarize]" >&2; exit 2; }
IDENTITY="${YAPP_RELEASE_IDENTITY:?Set YAPP_RELEASE_IDENTITY to your Developer ID Application certificate}"
PROFILE="${YAPP_NOTARY_PROFILE:-yapp-notary}"
ROOT="$PWD/build/distribution"
APP="$ROOT/Yapp.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
ARCH=$(uname -m)
DMG="$ROOT/Yapp-$VERSION-$ARCH.dmg"
if [[ "$MODE" == --notarize ]]; then
    # Validate authentication before spending time building. Credentials stay in Keychain.
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null
fi
security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null || {
    echo "Missing valid signing identity: $IDENTITY" >&2; exit 1;
}
for asset in AudioEncoder.mlmodelc MelSpectrogram.mlmodelc TextDecoder.mlmodelc tokenizer.json tokenizer_config.json config.json generation_config.json; do
    [[ -e "Models/$asset" ]] || { echo "Missing bundled model asset: $asset" >&2; exit 1; }
done
swift build -c release
BIN=$(swift build -c release --show-bin-path)
# Rebuild only the disposable distribution directory, never the local development app.
rm -rf "$ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Models" "$APP/Contents/Resources/Licenses"
cp "$BIN/Yapp" "$APP/Contents/MacOS/Yapp"
cp Info.plist "$APP/Contents/Info.plist"
ditto Models "$APP/Contents/Resources/Models"
cp Vendor/WhisperKit/LICENSE "$APP/Contents/Resources/Licenses/WhisperKit-LICENSE"
cp Vendor/WhisperKit/NOTICES "$APP/Contents/Resources/Licenses/WhisperKit-NOTICES"
cp Resources/Licenses/Whisper-LICENSE "$APP/Contents/Resources/Licenses/Whisper-LICENSE"
cp LICENSE "$APP/Contents/Resources/Licenses/Yapp-GPL-3.0.txt"
while IFS= read -r -d '' bundle; do
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done < <(find "$BIN" -maxdepth 1 -type d -name '*.bundle' -print0)
# SwiftPM links dependencies statically; fail if a future change introduces nested code.
if find "$APP/Contents/Resources" -type f -exec file {} + | grep -q 'Mach-O'; then
    echo "Nested executable code needs explicit inside-out signing." >&2; exit 1
fi
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements Resources/Release.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$MODE" == --notarize ]]; then
    ditto -c -k --keepParent "$APP" "$ROOT/Yapp.zip"
    xcrun notarytool submit "$ROOT/Yapp.zip" --keychain-profile "$PROFILE" --wait --output-format plist > "$ROOT/app-notarization.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print status' "$ROOT/app-notarization.plist")" == Accepted ]] || {
        echo "Notarization failed; inspect $ROOT/app-notarization.plist and fetch the submission log." >&2; exit 1;
    }
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi
mkdir "$ROOT/staging"
ditto "$APP" "$ROOT/staging/Yapp.app"
ln -s /Applications "$ROOT/staging/Applications"
hdiutil create -volname Yapp -srcfolder "$ROOT/staging" -format UDZO -ov "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
if [[ "$MODE" == --notarize ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format plist > "$ROOT/dmg-notarization.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print status' "$ROOT/dmg-notarization.plist")" == Accepted ]] || exit 1
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    echo "Notarized DMG: $DMG"
else
    echo "Signed DMG (NOT notarized; do not publish yet): $DMG"
fi
shasum -a 256 "$DMG" > "$DMG.sha256"
