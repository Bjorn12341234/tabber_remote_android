#!/usr/bin/env bash
# apple/scripts/release-ios.sh: build Tabber Spak and upload it to TestFlight in one go.
#
#   apple/scripts/release-ios.sh                  next build number, tests, archive, upload
#   apple/scripts/release-ios.sh --no-upload      the same, but export an .ipa locally (nothing sent)
#   apple/scripts/release-ios.sh --external       allow the build in external TestFlight groups
#   apple/scripts/release-ios.sh --build 12       use this build number instead of BUILD_NUMBER + 1
#
# Adapted from historia's app/scripts/release-ios.sh. Signs with the Apple account signed in to
# Xcode (automatic signing, -allowProvisioningUpdates): no App Store Connect API key. Uses Xcode
# 27.2 when /Applications/Xcode-27.2.app exists, otherwise the selected Xcode. Build output goes to
# /Volumes/Data/tabber_remote/xcode. After a successful upload the build number is committed,
# tagged ios-b<N> and pushed; otherwise nothing in git changes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
XCODE="/Volumes/Data/tabber_remote/xcode"
TEAM="VLBJ7VR4H8"
NUMBER_FILE="$HERE/BUILD_NUMBER"
UPLOAD=1
INTERNAL_ONLY=true
BUILD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-upload) UPLOAD=0 ;;
    --external) INTERNAL_ONLY=false ;;
    --build) BUILD="${2:?--build needs a number}"; shift ;;
    -h | --help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
  shift
done
if [ -d /Applications/Xcode-27.2.app ]; then export DEVELOPER_DIR=/Applications/Xcode-27.2.app/Contents/Developer; fi
fail() { echo "✗ $1 failed; last lines of $2:"; grep -E "error:|Error|failed" "$2" | tail -15 || tail -15 "$2"; exit 1; }

cd "$ROOT"
[ "$(git branch --show-current)" = "main" ] || { echo "✗ release from main"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "✗ commit everything first: a build matches a commit"; exit 1; }
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "✗ push main first"; exit 1; }

N="${BUILD:-$(( $(cat "$NUMBER_FILE" 2>/dev/null || echo 0) + 1 ))}"
mkdir -p "$XCODE"
LOG="$XCODE/release-b$N"
echo "• Tabber Spak build $N with $(xcodebuild -version | head -1)"

echo "• tests: RemoteKit and the protocol vectors"
(cd "$HERE/RemoteKit" && swift test --scratch-path "$XCODE/remotekit-build") > "$LOG-tests.log" 2>&1 || fail tests "$LOG-tests.log"
"$ROOT/.venv/bin/python" "$ROOT/tools/validate_vectors.py" >> "$LOG-tests.log" 2>&1 || fail vectors "$LOG-tests.log"

ARCHIVE="$XCODE/TabberSpak-b$N.xcarchive"
echo "• archive"
xcodebuild archive -project "$HERE/TabberSpak.xcodeproj" -scheme TabberSpak -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -derivedDataPath "$XCODE/derived-release" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$N" > "$LOG-archive.log" 2>&1 || fail archive "$LOG-archive.log"
GOT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVE/Products/Applications/TabberSpak.app/Info.plist")"
[ "$GOT" = "$N" ] || { echo "✗ the archive says build $GOT, not $N"; exit 1; }

OPTS="$XCODE/ExportOptions-b$N.plist"
cat > "$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "$UPLOAD" = 1 ] && echo upload || echo export)</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>testFlightInternalTestingOnly</key><$INTERNAL_ONLY/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
echo "• $([ "$UPLOAD" = 1 ] && echo upload || echo export)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" -exportPath "$XCODE/export-b$N" \
  -allowProvisioningUpdates > "$LOG-export.log" 2>&1 || fail export "$LOG-export.log"
[ "$UPLOAD" = 1 ] || { echo "✓ exported to $XCODE/export-b$N (nothing sent)"; exit 0; }

echo "$N" > "$NUMBER_FILE"
git add "$NUMBER_FILE"
git commit -q -m "Tabber Spak build $N uploaded to TestFlight"
git tag "ios-b$N"
git push -q && git push -q origin "ios-b$N"
echo "✓ build $N uploaded; Apple processes it for 5 to 15 minutes before TestFlight shows it"
