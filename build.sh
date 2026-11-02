#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# The certificate fingerprint is public; the private key stays in Keychain.
IDENTITY="${YAPP_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f .signing-identity ]]; then
    IFS= read -r IDENTITY < .signing-identity
fi
if [[ -z "$IDENTITY" ]]; then
    echo "Configure .signing-identity or YAPP_SIGNING_IDENTITY with a code-signing identity." >&2
    exit 1
fi
swift build -c release
APP="$PWD/build/Yapp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Models"
cp .build/release/Yapp "$APP/Contents/MacOS/Yapp"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE "$APP/Contents/Resources/Licenses/Yapp-GPL-3.0.txt"
cp -R Models/. "$APP/Contents/Resources/Models/"
find .build -path '*release/*.bundle' -maxdepth 5 -type d -exec cp -R {} "$APP/Contents/Resources/" \;
./script/embed-sparkle.sh "$APP" "$IDENTITY" none
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
