#!/usr/bin/env bash
# Fetches the testers' feedback reports from the kiosk into ./feedback/ (JSON + screenshot
# per report) and lists them. The admin account must be in the group "kiosk" (install.sh).
#   kiosk/fetch_feedback.sh <ssh-host> [target-dir]
set -euo pipefail

HOST="${1:?usage: fetch_feedback.sh <ssh-host> [target-dir]}"
DEST="${2:-feedback}"
read -r -a SSH_EXTRA <<< "${SSH_OPTS:-}"

mkdir -p "$DEST"
ssh "${SSH_EXTRA[@]}" "$HOST" 'test -d /var/lib/ost/feedback && tar -C /var/lib/ost/feedback -czf - . || true' \
  | tar -C "$DEST" -xzf - 2>/dev/null || true
count=$(find "$DEST" -name '*.json' | wc -l)
echo "$count reports in $DEST/"
for f in $(ls "$DEST"/*.json 2>/dev/null | sort); do
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("{time}  {kind:5}  {game}/{step}  {text}".format(**{k: r.get(k, "") for k in ("time","kind","game","step","text")}))' "$f"
done
