#!/bin/bash
# RemoteKit against Tabber Studio's real remote host on localhost (TLS 1.3, pinned).
# Usage: apple/scripts/interop.sh [path to tabber_studio]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
STUDIO="${1:-$HERE/../tabber_studio}"
BUILD="${REMOTEKIT_BUILD:-/Volumes/Data/tabber_remote/xcode/remotekit-build}"
"$STUDIO/venv/bin/python" "$HERE/tools/interop_host.py" "$STUDIO" > /tmp/tabber-interop.$$ 2>/tmp/tabber-interop.$$.log &
HOST=$!
trap 'kill $HOST 2>/dev/null || true; rm -f /tmp/tabber-interop.$$ /tmp/tabber-interop.$$.log' EXIT
for _ in $(seq 1 100); do [ -s /tmp/tabber-interop.$$ ] && break; sleep 0.1; done
LINE="$(head -1 /tmp/tabber-interop.$$)"
[ -n "$LINE" ] || { echo "the host did not start:"; cat /tmp/tabber-interop.$$.log; exit 1; }
cd "$HERE/apple/RemoteKit"
REMOTE_INTEROP="$LINE" swift test --scratch-path "$BUILD" --filter Interop
