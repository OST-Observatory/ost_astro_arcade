#!/usr/bin/env bash
# Builds the tablet app (debug-signed APK) and, with --install, puts it on a tablet
# connected by USB (USB debugging on).
#   android/build.sh [--install]
# One-time setup: android/setup.sh. The APK lands in build/android/.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/build/android/ost_space_lab.apk"
ADB="${OPT:-$HOME/.local/opt}/android-sdk/platform-tools/adb"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$OUT")"
echo "==> Export"
godot --headless --path "$REPO/godot" --export-debug "Android" "$OUT"
ls -lh "$OUT"

if (( INSTALL )); then
  echo "==> Install"
  "$ADB" install -r "$OUT"
  "$ADB" shell monkey -p de.unipotsdam.ost.spacelab -c android.intent.category.LAUNCHER 1 >/dev/null
fi
