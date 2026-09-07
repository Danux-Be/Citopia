#!/usr/bin/env bash
# Takes a fresh demo screenshot and posts it to the project's Discord
# channel. The webhook URL never lives in the repo: it is read from a
# local file (or $CITOPIA_WEBHOOK_FILE).
#
# Usage: tools/discord_shot.sh [caption]
set -euo pipefail
cd "$(dirname "$0")/.."

WEBHOOK_FILE="${CITOPIA_WEBHOOK_FILE:-$HOME/.citopia_discord_webhook}"
if [ ! -f "$WEBHOOK_FILE" ]; then
	echo "missing webhook file: $WEBHOOK_FILE" >&2
	echo "create a channel webhook in Discord (channel settings ->" >&2
	echo "Integrations -> Webhooks) and save its URL in that file" >&2
	exit 1
fi
WEBHOOK=$(cat "$WEBHOOK_FILE")

SHOT=/tmp/citopia_shot.png
attempt=1
while : ; do
	rm -f "$SHOT"
	DISPLAY="${DISPLAY:-:0}" timeout 150 godot --path . scenes/main.tscn \
		++ --demo --shot > /tmp/discord_shot.log 2>&1 || true
	# a real city capture is a rich PNG; a black/blank frame stays tiny
	if [ -f "$SHOT" ] && [ "$(stat -c%s "$SHOT")" -gt 50000 ]; then
		break
	fi
	echo "attempt $attempt produced a blank shot, retrying..." >&2
	attempt=$((attempt + 1))
	if [ "$attempt" -gt 3 ]; then
		echo "three blank shots in a row, see /tmp/discord_shot.log" >&2
		exit 1
	fi
done

HASH=$(git rev-parse --short HEAD)
STAMP=$(date '+%d/%m %H:%M')
CAPTION="${1:-Citopia — avancement du $STAMP (commit $HASH)}"

curl -sS -X POST "$WEBHOOK" \
	-F "payload_json={\"content\":\"$CAPTION\"}" \
	-F "file=@$SHOT;filename=citopia.png"
echo "posted: $CAPTION"
