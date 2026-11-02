#!/bin/bash
# Copy the pinned SwiftPM framework without flattening its symlinks, then sign
# its nested executables inside-out. Never use --deep as a signing strategy.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?app bundle path required}"
IDENTITY="${2:?code-signing identity required}"
STAMP="${3:-none}"
SOURCE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SOURCE" ]] || { echo "Resolve the pinned Sparkle package before packaging." >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources/Licenses"
# Remove only the previously staged framework, so old helpers cannot survive.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Licenses/Sparkle-LICENSE"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSION="$FRAMEWORK/Versions/B"
TIMESTAMP=(--timestamp=none)
[[ "$STAMP" != secure ]] || TIMESTAMP=(--timestamp)
for helper in "$VERSION/Autoupdate" "$VERSION/Updater.app" \
    "$VERSION/XPCServices/Downloader.xpc" "$VERSION/XPCServices/Installer.xpc"; do
    [[ -e "$helper" ]] || { echo "Missing Sparkle helper: $helper" >&2; exit 1; }
    codesign --force --sign "$IDENTITY" --options runtime "${TIMESTAMP[@]}" \
        --preserve-metadata=entitlements "$helper"
done
codesign --force --sign "$IDENTITY" --options runtime "${TIMESTAMP[@]}" "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
