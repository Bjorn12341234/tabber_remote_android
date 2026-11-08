#!/usr/bin/env bash
# android/scripts/pair-check.sh: TA1's end-to-end check on the emulator. Tabber Studio's real
# remote host runs on this laptop (tools/interop_host.py, as interop.sh), the debug app gets the
# host's pairing link the way the phone's camera hands it over, Pair is tapped through the
# accessibility tree, and the screen must say the phone paired. Saves shots/pair-check.png.
#
#   android/scripts/emulator.sh start && android/scripts/pair-check.sh [path to Tabber Studio]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" JAVA_HOME="${JAVA_HOME:-/opt/android-studio/jbr}"
ADB="$ANDROID_HOME/platform-tools/adb"
APP=com.tabberspak.app.debug
STUDIO="${1:-}"
if [ -z "$STUDIO" ]; then
  for candidate in "$HERE/../tabber_studio_linux" "$HERE/../tabber_studio"; do
    [ -d "$candidate/remote_host" ] && { STUDIO="$candidate"; break; }
  done
fi
PYTHON="$STUDIO/.venv/bin/python"; [ -x "$PYTHON" ] || PYTHON="$STUDIO/venv/bin/python"
"$ADB" get-state > /dev/null 2>&1 || { echo "✗ no emulator: android/scripts/emulator.sh start"; exit 1; }

OUT="$(mktemp "${TMPDIR:-/tmp}/tabberspak-pair.XXXXXX")"
QT_QPA_PLATFORM=offscreen "$PYTHON" "$HERE/tools/interop_host.py" "$STUDIO" > "$OUT" 2> "$OUT.log" &
HOST=$!
trap 'kill $HOST 2>/dev/null || true; rm -f "$OUT" "$OUT.log" "$OUT.xml"' EXIT
for _ in $(seq 1 100); do [ -s "$OUT" ] && break; sleep 0.1; done
LINE="$(head -1 "$OUT")"
[ -n "$LINE" ] || { echo "✗ the host did not start:"; cat "$OUT.log"; exit 1; }
LINK="$(python3 -c '
import json, sys, urllib.parse
h = json.loads(sys.argv[1])
q = urllib.parse.urlencode({"v": "1", "id": h["host_id"], "name": "Interop Studio", "spki": h["pin"],
                            "tok": h["token"], "hosts": "10.0.2.2:%d" % h["port"]}, quote_via=urllib.parse.quote)
print("tabber-remote://pair?" + q)' "$LINE")"

(cd "$HERE/android" && ./gradlew :app:assembleDebug -q --console=plain 2>&1 | grep -v "Unable to strip" || true)
"$ADB" install -r -t "$HERE/android/app/build/outputs/apk/debug/app-debug.apk" > /dev/null
"$ADB" shell am force-stop "$APP"
"$ADB" shell am start -W -a android.intent.action.VIEW -d "'$LINK'" "$APP" > /dev/null

dump() { "$ADB" exec-out uiautomator dump /dev/tty 2> /dev/null | sed 's/UI hierchary dumped to: \/dev\/tty//' > "$OUT.xml"; }
bounds() { # the centre of the first node whose text is $1
  python3 -c '
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for node in root.iter("node"):
    if node.get("text") == sys.argv[2]:
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        print((x1 + x2) // 2, (y1 + y2) // 2); break' "$OUT.xml" "$1"
}
status() { python3 -c '
import sys, xml.etree.ElementTree as ET
for node in ET.parse(sys.argv[1]).getroot().iter("node"):
    if node.get("resource-id", "").endswith("status") or node.get("text", "").startswith(("Pair", "Paired", "No answer", "Connecting", "The computer", "Interop")):
        print(node.get("text")); break' "$OUT.xml"; }

for _ in $(seq 1 30); do dump; [ -n "$(bounds Pair)" ] && break; sleep 0.5; done
XY="$(bounds Pair)"; [ -n "$XY" ] || { echo "✗ no Pair button"; exit 1; }
# shellcheck disable=SC2086
"$ADB" shell input tap $XY
RESULT=""
for _ in $(seq 1 40); do
  sleep 0.5; dump
  RESULT="$(status || true)"
  case "$RESULT" in Paired*|No\ answer*|The\ computer*|*"said no"*) break ;; esac
done
mkdir -p "$HERE/android/shots"
"$ADB" exec-out screencap -p > "$HERE/android/shots/pair-check.png"
echo "$RESULT"
case "$RESULT" in Paired*) echo "✓ paired on the emulator (android/shots/pair-check.png)" ;; *) echo "✗ did not pair"; exit 1 ;; esac
