#!/usr/bin/env bash
# android/scripts/emulator.sh: the test phone on this laptop, shared with Storman and GoPast
# (GoPast_Light: a 720x1600 phone, Android 16, two cores, low priority, quick boot from a
# snapshot; ~/projects/historia/tools/android/emulator.sh makes it if it is missing).
#
#   android/scripts/emulator.sh start [--window]   boot it (headless; --window shows it)
#   android/scripts/emulator.sh stop               close it, saving the snapshot
#
# Always -no-audio: the laptop's speakers are the owner's, and Tabber Spak plays nothing itself.
# The emulator reaches this laptop's own localhost as 10.0.2.2, which is how it meets a
# Tabber Studio host running here.
set -euo pipefail
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
AVD="${TABBERSPAK_AVD:-GoPast_Light}"
LOG="${TMPDIR:-/tmp}/tabberspak-emulator.log"

start() {
  local window=-no-window
  [ "${1:-}" = --window ] && window=""
  "$ADB" get-state > /dev/null 2>&1 && { echo "a phone or emulator is already connected"; exit 0; }
  [ -f "$HOME/.android/avd/$AVD.avd/config.ini" ] \
    || { echo "no emulator $AVD: ~/projects/historia/tools/android/emulator.sh start makes it"; exit 1; }
  # shellcheck disable=SC2086
  nohup nice -n 15 "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -gpu "${TABBERSPAK_GPU:-swangle_indirect}" -cores 2 \
    -no-boot-anim -no-audio $window > "$LOG" 2>&1 &
  echo "• booting $AVD (${window:-with a window}, no audio, log $LOG)"
  "$ADB" wait-for-device
  until [ "$("$ADB" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ]; do
    pgrep qemu-system > /dev/null || { echo "✗ the emulator stopped; see $LOG"; exit 1; }
    sleep 2
  done
  echo "✓ $AVD is up"
}

stop() {
  "$ADB" emu kill > /dev/null 2>&1 && echo "✓ stopped (snapshot saved for a quick boot)" || echo "not running"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  stop) stop ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
