#!/usr/bin/env bash
# RemoteKit against Tabber Studio's real remote host on localhost (TLS 1.3, pinned), as
# apple/scripts/interop.sh. Usage: android/scripts/interop.sh [path to a Tabber Studio checkout]
# (default: the Linux one beside this repository, then the macOS one).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
STUDIO="${1:-}"
if [ -z "$STUDIO" ]; then
  for candidate in "$HERE/../tabber_studio_linux" "$HERE/../tabber_studio"; do
    [ -d "$candidate/remote_host" ] && { STUDIO="$candidate"; break; }
  done
fi
[ -n "$STUDIO" ] && [ -d "$STUDIO/remote_host" ] || { echo "✗ no Tabber Studio checkout with remote_host"; exit 1; }
PYTHON="$STUDIO/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON="$STUDIO/venv/bin/python"
export JAVA_HOME="${JAVA_HOME:-/opt/android-studio/jbr}"
OUT="$(mktemp "${TMPDIR:-/tmp}/tabber-interop.XXXXXX")"
QT_QPA_PLATFORM=offscreen "$PYTHON" "$HERE/tools/interop_host.py" "$STUDIO" > "$OUT" 2> "$OUT.log" &
HOST=$!
trap 'kill $HOST 2>/dev/null || true; rm -f "$OUT" "$OUT.log"' EXIT
for _ in $(seq 1 100); do [ -s "$OUT" ] && break; sleep 0.1; done
LINE="$(head -1 "$OUT")"
[ -n "$LINE" ] || { echo "✗ the host did not start:"; cat "$OUT.log"; exit 1; }
cd "$HERE/android"
REMOTE_INTEROP="$LINE" ./gradlew :remotekit:test --tests 'com.tabberspak.remotekit.InteropTests' --console=plain
