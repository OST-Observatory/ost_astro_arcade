#!/usr/bin/env bash
# Builds a release on the dev machine and deploys it to the kiosk.
#   kiosk/deploy.sh <ssh-host> [--no-build]
# The SSH user needs sudo on the kiosk (the admin account, not "kiosk"); a sudo password is
# asked for in the terminal. Extra ssh options: SSH_OPTS="-F /dev/null" kiosk/deploy.sh ...
# Without rsync on the dev machine the upload goes as a tar stream over ssh.
# Releases go to /opt/ost/releases/<timestamp>; /opt/ost/current points to the active one.
# Roll back:  ssh <host> 'sudo ln -sfn /opt/ost/releases/<older> /opt/ost/current && sudo systemctl restart ost-arcade'
set -euo pipefail

HOST="${1:?usage: deploy.sh <ssh-host> [--no-build]}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/build/linux"
STAMP="$(date +%Y%m%d-%H%M%S)-$(git -C "$REPO" rev-parse --short HEAD)"
KEEP=3
read -r -a SSH_EXTRA <<< "${SSH_OPTS:-}"
SSH=(ssh "${SSH_EXTRA[@]}")

if [[ "${2:-}" != "--no-build" ]]; then
  echo "==> Tests"
  godot --headless --path "$REPO/godot" -s res://tests/run_tests.gd
  echo "==> Export"
  mkdir -p "$BUILD"
  godot --headless --path "$REPO/godot" --export-release "Linux" "$BUILD/ost_astro_arcade.x86_64"
fi

echo "==> Upload $STAMP"
"${SSH[@]}" -t "$HOST" "sudo install -d -m 755 /opt/ost/releases/$STAMP && sudo chown \$(id -u) /opt/ost/releases/$STAMP"
if command -v rsync >/dev/null; then
  rsync -az --info=progress2 -e "${SSH[*]}" "$BUILD/" "$HOST:/opt/ost/releases/$STAMP/"
else
  tar -C "$BUILD" -czf - . | "${SSH[@]}" "$HOST" "tar -xzf - -C /opt/ost/releases/$STAMP"
fi

echo "==> Activate + restart"
"${SSH[@]}" -t "$HOST" "sudo chown -R root:root /opt/ost/releases/$STAMP \
  && sudo ln -sfn /opt/ost/releases/$STAMP /opt/ost/current \
  && sudo systemctl restart ost-arcade \
  && cd /opt/ost/releases && ls -1t | tail -n +$((KEEP + 1)) | xargs -r sudo rm -rf"
echo "Deployed $STAMP to $HOST"
