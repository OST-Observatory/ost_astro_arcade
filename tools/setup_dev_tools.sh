#!/usr/bin/env bash
# Installs the pinned dev tools for ost_astro_arcade into ~/.local/opt (no root needed).
# Works from a normal terminal and from the Flatpak VSCodium sandbox (shared $HOME).
#   Godot 4.7.2-stable, Blender 4.5.14 LTS, uv (latest release)
# Every download is checked against the publisher's checksum file.
set -euo pipefail

GODOT_VER=4.7.2-stable
BLENDER_VER=4.5.14
OPT="$HOME/.local/opt"
BIN="$HOME/.local/bin"
DL="$OPT/dl"
mkdir -p "$DL" "$BIN"
cd "$DL"

echo "==> Godot $GODOT_VER"
GZ="Godot_v${GODOT_VER}_linux.x86_64.zip"
curl -fsSL -o "$GZ" "https://github.com/godotengine/godot/releases/download/$GODOT_VER/$GZ"
curl -fsSL -o godot-SHA512-SUMS.txt "https://github.com/godotengine/godot/releases/download/$GODOT_VER/SHA512-SUMS.txt"
grep " $GZ\$" godot-SHA512-SUMS.txt | sha512sum -c -
mkdir -p "$OPT/godot-$GODOT_VER"
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$GZ" "$OPT/godot-$GODOT_VER"
chmod +x "$OPT/godot-$GODOT_VER/Godot_v${GODOT_VER}_linux.x86_64"
ln -sfn "$OPT/godot-$GODOT_VER/Godot_v${GODOT_VER}_linux.x86_64" "$BIN/godot"

echo "==> Blender $BLENDER_VER LTS"
BT="blender-${BLENDER_VER}-linux-x64.tar.xz"
curl -fsSL -o "$BT" "https://download.blender.org/release/Blender${BLENDER_VER%.*}/$BT"
curl -fsSL "https://download.blender.org/release/Blender${BLENDER_VER%.*}/blender-${BLENDER_VER}.sha256" \
  | grep " $BT\$" | sha256sum -c -
tar -xf "$BT" -C "$OPT"
ln -sfn "$OPT/blender-${BLENDER_VER}-linux-x64/blender" "$BIN/blender"

echo "==> uv"
UV_TAG=$(curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
UT="uv-x86_64-unknown-linux-gnu.tar.gz"
curl -fsSL -o "$UT" "https://github.com/astral-sh/uv/releases/download/$UV_TAG/$UT"
curl -fsSL "https://github.com/astral-sh/uv/releases/download/$UV_TAG/$UT.sha256" \
  | awk -v f="$UT" '{print $1"  "f}' | sha256sum -c -
tar -xzf "$UT"
install -m 755 uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx "$BIN/"

rm -rf "$GZ" "$BT" "$UT" uv-x86_64-unknown-linux-gnu
echo
"$BIN/godot" --version
"$BIN/blender" --version | head -1
"$BIN/uv" --version
echo "Done. Make sure $BIN is on your PATH."
