#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$PWD/build/Yapp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Models"
cp .build/release/Yapp "$APP/Contents/MacOS/Yapp"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Models/. "$APP/Contents/Resources/Models/"
find .build -path '*release/*.bundle' -maxdepth 5 -type d -exec cp -R {} "$APP/Contents/Resources/" \;
codesign --force --deep --sign - "$APP"
echo "Built $APP"
