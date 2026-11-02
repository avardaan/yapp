#!/bin/bash
# Use only after notarization/stapling. Private Ed25519 key stays in Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHIVES="${1:?directory containing notarized update archives required}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT="${YAPP_SPARKLE_ACCOUNT:-zeroslop.yapp}"
PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)
[[ "$PUBLIC_KEY" == "$EXPECTED" ]] || { echo "Keychain update-signing key does not match Info.plist." >&2; exit 1; }
# Preserve past feed entries. Only signed archives, not models or source, go here.
if [[ -f website/appcast.xml && ! -f "$ARCHIVES/appcast.xml" ]]; then
    cp website/appcast.xml "$ARCHIVES/appcast.xml"
fi
if [[ -f "docs/releases/$VERSION.md" ]]; then
    for archive in "$ARCHIVES"/Yapp-"$VERSION"-*.zip; do
        cp "docs/releases/$VERSION.md" "${archive%.zip}.md"
    done
fi
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
    --embed-release-notes --link https://yapp.now/ \
    --download-url-prefix "https://github.com/avardaan/yapp/releases/download/v$VERSION/" \
    "$ARCHIVES"
# Stage locally; publish only after the archive is uploaded to its GitHub Release.
echo "Generated $ARCHIVES/appcast.xml (publish after uploading its archive)."
