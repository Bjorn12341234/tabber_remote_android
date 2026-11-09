#!/usr/bin/env bash
# android/scripts/release-android.sh: a build of Tabber Spak for Google Play's testing tracks, the
# Android twin of apple/scripts/release-ios.sh, as Storman's android/scripts/release-android.sh.
#
#   android/scripts/release-android.sh             BUILD_NUMBER + 1: checks, signed .aab, the
#                                                  emulator's smoke test, then commit, tag
#                                                  android-b<N> and push
#   android/scripts/release-android.sh --local     the same from any branch or a dirty tree;
#                                                  BUILD_NUMBER put back, nothing committed
#   android/scripts/release-android.sh --build 12  this build number instead of BUILD_NUMBER + 1
#
# Signs with the upload key named in ~/.gradle/gradle.properties (TABBERSPAK_UPLOAD_*); Play
# re-signs with the app key. The .aab goes to ~/tabber-spak-releases/: upload it in Play Console ›
# Test and release › Testing › Internal testing › Create new release. A build matches a pushed
# commit on main, as on iOS.
set -euo pipefail
ANDROID="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$ANDROID/.." && pwd)"
OUT="$HOME/tabber-spak-releases"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-/opt/android-studio/jbr}"
ADB="$ANDROID_HOME/platform-tools/adb"

LOCAL=0
BUILD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL=1 ;;
    --build) BUILD="${2:?--build needs a number}"; shift ;;
    -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
  shift
done

fail() { # step, log
  echo "✗ $1 failed; last lines of $2:"
  grep -E "error|Error|FAIL|✗|What went wrong" "$2" | tail -15 || tail -15 "$2"
  exit 1
}

cd "$ROOT"
grep -q '^TABBERSPAK_UPLOAD_STORE_FILE=' "$GRADLE_PROPS" 2> /dev/null \
  || { echo "✗ no upload key: TABBERSPAK_UPLOAD_* missing from $GRADLE_PROPS"; exit 1; }
# An uploaded build must match a pushed commit on main; a local build may come from anything.
if [ "$LOCAL" = 0 ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "✗ not on main"; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "✗ uncommitted work: commit first"; exit 1; }
  git fetch -q origin
  [ "$(git rev-list --count origin/main..HEAD)" = 0 ] || { echo "✗ main is ahead of origin: push first"; exit 1; }
fi

CURRENT="$(tr -d '[:space:]' < "$ANDROID/BUILD_NUMBER")"
N="${BUILD:-$((CURRENT + 1))}"
[ "$N" -gt "$CURRENT" ] 2> /dev/null || { echo "✗ build $N is not above BUILD_NUMBER's $CURRENT"; exit 1; }
VERSION="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' "$ROOT/apple/TabberSpak.xcodeproj/project.pbxproj" | head -1)"
[ -n "$VERSION" ] || { echo "✗ no MARKETING_VERSION in the iPhone project"; exit 1; }
DONE=0
trap '[ "$DONE" = 1 ] || echo "$CURRENT" > "$ANDROID/BUILD_NUMBER"' EXIT
echo "$N" > "$ANDROID/BUILD_NUMBER"
echo "Tabber Spak $VERSION ($N)$([ "$LOCAL" = 0 ] || echo ', a local build: BUILD_NUMBER put back after')"

mkdir -p "$OUT"
LOG="$OUT/release-b$N"

echo "· RemoteKit's tests, the app's unit tests, lint"
(cd "$ANDROID" && ./gradlew :remotekit:test :app:testDebugUnitTest :app:lintRelease --console=plain) \
  > "$LOG-checks.log" 2>&1 || fail "the checks" "$LOG-checks.log"

echo "· bundle and the same build as an APK, minified"
(cd "$ANDROID" && ./gradlew clean :app:bundleRelease :app:assembleRelease --console=plain) > "$LOG-bundle.log" 2>&1 \
  || fail "the bundle" "$LOG-bundle.log"

# What Play gets: this build number, the upload key, and nothing from development.
AAB="$ANDROID/app/build/outputs/bundle/release/app-release.aab"
APK="$ANDROID/app/build/outputs/apk/release/app-release.apk"
[ -f "$AAB" ] || { echo "✗ no $AAB"; exit 1; }
MANIFEST="$(find "$ANDROID/app/build/intermediates" -path '*release*' -name AndroidManifest.xml -print0 | xargs -0 grep -l 'versionCode' | head -1)"
grep -q "android:versionCode=\"$N\"" "$MANIFEST" || { echo "✗ the bundle's manifest does not have versionCode $N"; exit 1; }
if grep -q 'android:debuggable="true"' "$MANIFEST"; then echo "✗ a debuggable build"; exit 1; fi
SIGNER="$("$JAVA_HOME/bin/keytool" -printcert -jarfile "$AAB" 2> /dev/null | sed -n 's/^\s*SHA256: //p' | head -1)"
[ "$SIGNER" = "$(tr -d '[:space:]' < "$ANDROID/store/upload-certificate.sha256")" ] \
  || { echo "✗ the bundle is not signed with the upload key (android/store/upload-certificate.sha256)"; exit 1; }

# The minified build on the emulator, when one runs: the welcome, then the demo connects. (A phone
# with Play's build would refuse this one's signature, so only the emulator is used.)
if "$ADB" get-state > /dev/null 2>&1 && [ "$("$ADB" shell getprop ro.kernel.qemu 2> /dev/null | tr -d '\r')" = 1 ]; then
  echo "· the minified build on the emulator: the demo"
  "$ADB" install -r "$APK" > "$LOG-smoke.log" 2>&1 || fail "installing the release build" "$LOG-smoke.log"
  "$ADB" shell am force-stop com.tabberspak.app
  "$ADB" shell pm clear com.tabberspak.app >> "$LOG-smoke.log" 2>&1
  "$ADB" shell am start -W -n com.tabberspak.app/.MainActivity >> "$LOG-smoke.log" 2>&1
  dump() { "$ADB" exec-out uiautomator dump /dev/tty 2> /dev/null; }
  centre() { # resource id: the middle of its bounds
    dump | tr '<' '\n' | grep "resource-id=\"$1\"" | head -1 | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' \
      | awk '{ print int(($1 + $3) / 2), int(($2 + $4) / 2) }'
  }
  for _ in $(seq 1 20); do [ -n "$(centre demo)" ] && break; sleep 0.5; done
  [ -n "$(centre demo)" ] || { echo "✗ the minified build shows no welcome (no 'demo' button)"; exit 1; }
  # shellcheck disable=SC2046
  "$ADB" shell input tap $(centre demo)
  CONNECTED=0
  for _ in $(seq 1 30); do dump | grep -q 'Demo Studio, connected' && { CONNECTED=1; break; }; sleep 0.5; done
  "$ADB" shell am force-stop com.tabberspak.app
  "$ADB" uninstall com.tabberspak.app >> "$LOG-smoke.log" 2>&1 || true
  [ "$CONNECTED" = 1 ] || { echo "✗ the minified build's demo never connected"; exit 1; }
else
  echo "· no emulator: the minified build was not started (android/scripts/emulator.sh start)"
fi

FINAL="$OUT/TabberSpak-$VERSION-b$N.aab"
cp "$AAB" "$FINAL"
echo "· $(du -h "$FINAL" | cut -f1) signed by $SIGNER"

if [ "$LOCAL" = 1 ]; then
  echo "✓ $FINAL (a local build: BUILD_NUMBER unchanged, nothing committed)"
  exit 0
fi

DONE=1
git add "$ANDROID/BUILD_NUMBER"
git commit -q -m "Tabber Spak (Android): build $N for Google Play"
git tag "android-b$N"
git push -q origin main && git push -q origin "android-b$N"
echo "✓ $FINAL"
echo "  upload it in Play Console › Test and release › Testing › Internal testing › Create new release"
echo "  committed and tagged android-b$N, pushed to origin; logs in $LOG-*.log"
