#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Point the website download button at a published versioned DMG, so the
# downloaded file is named yapp-<version>-<arch>.dmg. Run only after uploading it.
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)}"
ARCH="${2:-arm64}"
URL="https://github.com/avardaan/yapp/releases/download/v$VERSION/yapp-$VERSION-$ARCH.dmg"
curl -fsSIL -o /dev/null "$URL" || { echo "Not downloadable yet: $URL" >&2; exit 1; }
sed -E -i '' "s#https://github\.com/avardaan/yapp/releases/[^\"]*\.dmg#$URL#" website/index.html
grep -qF "$URL" website/index.html || { echo "Download link not found in website/index.html" >&2; exit 1; }
echo "Website download link: $URL"
