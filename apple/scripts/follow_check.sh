#!/bin/bash
# TR6 end to end: Tabber Spak in the Simulator pairs with a headless Tabber
# Studio (tools/stage_host.py), the computer comes back on another port, and
# the app must find it again by itself, through Bonjour, without pairing.
#
#   apple/scripts/follow_check.sh [path to tabber_studio]
#
# The host listens on every interface for about a minute (stage_host.py says
# why); run it on a trusted network. Needs the app built for the Simulator:
#   xcodebuild build -project apple/TabberSpak.xcodeproj -scheme TabberSpak \
#     -destination 'id=<simulator>' -derivedDataPath /Volumes/Data/tabber_remote/xcode/derived
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
STUDIO="$(cd "${1:-$HERE/../tabber_studio}" && pwd)"
APP="${TABBER_SPAK_APP:-/Volumes/Data/tabber_remote/xcode/derived/Build/Products/Debug-iphonesimulator/TabberSpak.app}"
SIM="${SIMULATOR:-booted}"
WORK="$(mktemp -d /tmp/tabber-follow.XXXXXX)"
PY="$STUDIO/venv/bin/python"
FIRST_PORT="${FIRST_PORT:-9481}"
SECOND_PORT="${SECOND_PORT:-9482}"
HOST=""
trap '[ -n "$HOST" ] && kill "$HOST" 2>/dev/null; xcrun simctl terminate "$SIM" studio.tabber.spak 2>/dev/null; rm -rf "$WORK"' EXIT

start_host() {   # $1 port, $2 output file
  "$PY" "$HERE/tools/stage_host.py" --studio "$STUDIO" --state "$WORK/state" --port "$1" --seconds 120 > "$2" 2> "$2.log" &
  HOST=$!
  for _ in $(seq 1 300); do grep -q '"link"' "$2" 2>/dev/null && return 0; sleep 0.1; done
  echo "✗ the host did not start:"; tail -20 "$2.log"; exit 1
}

wait_for() {     # $1 file, $2 text, $3 seconds
  for _ in $(seq 1 $(( $3 * 10 ))); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done
  return 1
}

echo "• the computer on port $FIRST_PORT"
start_host "$FIRST_PORT" "$WORK/first"
LINK="$(grep '"link"' "$WORK/first" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["link"])')"
xcrun simctl terminate "$SIM" studio.tabber.spak 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
echo "• the phone pairs from the link"
xcrun simctl launch "$SIM" studio.tabber.spak -reset -pair-link "$LINK" > /dev/null
wait_for "$WORK/first" '"activity": "paired' 20 || { echo "✗ the phone did not pair"; cat "$WORK/first"; exit 1; }
wait_for "$WORK/first" ' connected"' 20 || { echo "✗ the phone did not connect after pairing"; cat "$WORK/first"; exit 1; }
xcrun simctl io "$SIM" screenshot "$WORK/paired.png" > /dev/null 2>&1 || true

echo "• the computer goes away and comes back on port $SECOND_PORT"
kill "$HOST"; wait "$HOST" 2>/dev/null || true
start_host "$SECOND_PORT" "$WORK/second"
START=$(python3 -c 'import time; print(time.time())')
if wait_for "$WORK/second" ' connected"' 45; then
  END=$(python3 -c 'import time; print(time.time())')
  python3 -c "import sys; print(f'✓ the phone found the computer on its new port by itself, {float(sys.argv[2]) - float(sys.argv[1]):.1f} s after it came back')" "$START" "$END"
else
  echo "✗ the phone did not find the computer again"; cat "$WORK/second"; exit 1
fi
if grep -q '"activity": "paired' "$WORK/second"; then echo "✗ it paired again instead"; exit 1; fi
xcrun simctl io "$SIM" screenshot "${SCREENSHOT:-$WORK/after.png}" > /dev/null 2>&1 || true
