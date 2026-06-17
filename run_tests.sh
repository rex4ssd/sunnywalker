#!/usr/bin/env bash
# SunnyWalker — run the unit test suite on a simulator.
#
#   ./run_tests.sh                 # default device (iPhone 14 Plus)
#   ./run_tests.sh "iPhone 16"     # pick another simulator by name
#   ./run_tests.sh "iPhone 16" 26.5  # pin name + OS version
#
# Notes:
#  - Scheme is SunnyWalker; ⌘U in Xcode runs the same suite.
#  - Min target is iOS 26 (AlarmKit), so the simulator must be an iOS 26.x device.
#  - Grandfather tests live in GrandfatherSignalTests (StoreService.originalAppVersion cutoff).

set -euo pipefail

# Always run from the project root (dir this script lives in).
cd "$(dirname "$0")"

SCHEME="SunnyWalker"
DEVICE="${1:-iPhone 14 Plus}"
OS="${2:-}"

if [[ -n "$OS" ]]; then
  DEST="platform=iOS Simulator,name=${DEVICE},OS=${OS}"
else
  DEST="platform=iOS Simulator,name=${DEVICE}"
fi

echo "▶︎ xcodebuild test  scheme=${SCHEME}  destination='${DEST}'"
echo

# xcpretty prettifies output if installed; otherwise fall back to raw xcodebuild.
if command -v xcpretty >/dev/null 2>&1; then
  set -o pipefail
  xcodebuild test -scheme "$SCHEME" -destination "$DEST" | xcpretty
else
  xcodebuild test -scheme "$SCHEME" -destination "$DEST"
fi

status=$?
echo
if [[ $status -eq 0 ]]; then
  echo "✅ tests passed"
else
  echo "❌ tests failed (exit $status)"
  echo "   If it's a device/OS mismatch, list installed sims with:"
  echo "     xcrun simctl list devices available"
fi
exit $status
