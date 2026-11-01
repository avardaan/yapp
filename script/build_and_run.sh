#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
pkill -x Yapp >/dev/null 2>&1 || true
./build.sh
APP="$PWD/build/Yapp.app"
case "$MODE" in
  run) /usr/bin/open -n "$APP" ;;
  --verify) /usr/bin/open -n "$APP"; sleep 2; pgrep -x Yapp ;;
  --smoke) /usr/bin/open -n "$APP" --args --smoke-audio "$2" ;;
  --debug) lldb -- "$APP/Contents/MacOS/Yapp" ;;
  *) echo "Usage: $0 [run|--verify|--debug|--smoke audio.wav]"; exit 2 ;;
esac
