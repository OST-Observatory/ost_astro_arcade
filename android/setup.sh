#!/usr/bin/env bash
# One-time setup of the Android build tools (see android/README.md):
#   JDK 17, Android SDK (platform-tools, build-tools, platform), Godot's Android templates,
#   a debug keystore, and the paths in Godot's editor settings.
# Everything goes to ~/.local/opt (OPT=... to change). Downloads are checked against pinned
# checksums. The Android SDK licence is shown by sdkmanager and has to be accepted by you.
set -euo pipefail

OPT="${OPT:-$HOME/.local/opt}"
DL="$OPT/dl/android"
GODOT_VERSION="4.7.2"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
TEMPLATES="$DATA/export_templates/$GODOT_VERSION.stable"
JDK="$OPT/jdk17"
SDK="$OPT/android-sdk"
KEYSTORE="$DATA/keystores/debug.keystore"
# Versions from config.gradle in Godot's android_source.zip.
SDK_PACKAGES=("platform-tools" "build-tools;36.1.0" "platforms;android-36")

CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip"
CMDLINE_SHA1="e025545c62a8e64c7559119566a569fb1dec5f60"
JDK_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.21%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.21_9.tar.gz"
JDK_SHA256="8b9b611d917e3dfd8419d3566b5949226f69b052fed7e109c1368add1dfe8711"
TPZ_URL="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v$GODOT_VERSION-stable_export_templates.tpz"
TPZ_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"

fetch() {  # fetch <url> <file> <sha-tool> <sum>
  local url=$1 file=$2 tool=$3 sum=$4
  if [[ ! -f "$DL/$file" ]] || ! echo "$sum  $DL/$file" | "$tool" -c --status; then
    echo "==> Download $file"
    curl -fL --progress-bar -o "$DL/$file" "$url"
    echo "$sum  $DL/$file" | "$tool" -c
  fi
}

mkdir -p "$DL"
fetch "$CMDLINE_URL" cmdline-tools.zip sha1sum "$CMDLINE_SHA1"
fetch "$JDK_URL" jdk17.tar.gz sha256sum "$JDK_SHA256"
fetch "$TPZ_URL" templates.tpz sha512sum "$TPZ_SHA512"

if [[ ! -x "$JDK/bin/java" ]]; then
  echo "==> JDK 17 -> $JDK"
  mkdir -p "$JDK"
  tar -xzf "$DL/jdk17.tar.gz" -C "$JDK" --strip-components=1
fi

if [[ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "==> Android command-line tools -> $SDK"
  rm -rf "$SDK/cmdline-tools/latest" "$SDK/cmdline-tools/cmdline-tools"
  mkdir -p "$SDK/cmdline-tools"
  unzip -q "$DL/cmdline-tools.zip" -d "$SDK/cmdline-tools"
  mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
fi

export JAVA_HOME="$JDK"
SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
echo "==> Android SDK licences (please read and accept)"
"$SDKMANAGER" --sdk_root="$SDK" --licenses
echo "==> Android SDK packages: ${SDK_PACKAGES[*]}"
"$SDKMANAGER" --sdk_root="$SDK" "${SDK_PACKAGES[@]}"

if [[ ! -f "$TEMPLATES/android_source.zip" ]]; then
  echo "==> Godot Android templates -> $TEMPLATES"
  mkdir -p "$TEMPLATES"
  unzip -q -j -o "$DL/templates.tpz" templates/android_debug.apk templates/android_release.apk \
    templates/android_source.zip -d "$TEMPLATES"
fi

if [[ ! -f "$KEYSTORE" ]]; then
  echo "==> Debug keystore -> $KEYSTORE"
  mkdir -p "$(dirname "$KEYSTORE")"
  "$JDK/bin/keytool" -genkeypair -keystore "$KEYSTORE" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# Godot reads the SDK paths from its editor settings, not from the environment.
SETTINGS=$(ls "$CONFIG"/editor_settings-4.*.tres 2>/dev/null | tail -n 1 || true)
if [[ -n "$SETTINGS" ]]; then
  echo "==> Paths in $SETTINGS"
  sed -i \
    -e "s|^export/android/java_sdk_path = .*|export/android/java_sdk_path = \"$JDK\"|" \
    -e "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$SDK\"|" \
    -e "s|^export/android/debug_keystore = .*|export/android/debug_keystore = \"$KEYSTORE\"|" \
    "$SETTINGS"
  grep "^export/android/\(java_sdk_path\|android_sdk_path\|debug_keystore\) " "$SETTINGS"
else
  echo "No Godot editor settings found in $CONFIG; open the Godot editor once and run this again."
fi
echo "Done. Build with android/build.sh"
