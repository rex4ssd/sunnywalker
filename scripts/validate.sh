#!/usr/bin/env bash
# scripts/validate.sh — build + test + lint SunnyWalker
# Called by AI B (Validator) inside the orchestrator pipeline.

set -uo pipefail   # do NOT set -e; we want to capture failures, not abort

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="${SCHEME:-SunnyWalker}"
DERIVED="$REPO_ROOT/.build"

# 動態偵測可用 simulator：優先找 iPhone 17，找不到就取第一個 available iPhone
if [ -z "${DESTINATION:-}" ]; then
  SIM_NAME=$(xcrun simctl list devices available 2>/dev/null \
    | grep -E "^\s+iPhone" | sed 's/^\s*//' | sed 's/ (.*$//' | head -1)
  DESTINATION="platform=iOS Simulator,name=${SIM_NAME:-iPhone 17}"
  echo "auto-detected simulator: $DESTINATION"
fi

echo "=== validate.sh starting at $(date -Iseconds) ==="
echo "repo:        $REPO_ROOT"
echo "scheme:      $SCHEME"
echo "destination: $DESTINATION"
echo ""

# ---------- 1. xcodebuild build ----------
echo "--- [1/3] xcodebuild build ---"
if [ ! -d "$REPO_ROOT/SunnyWalker.xcodeproj" ] && [ ! -d "$REPO_ROOT/SunnyWalker.xcworkspace" ]; then
  echo "!! No Xcode project found. Skipping build."
  BUILD_RC=99
else
  xcodebuild \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    -quiet \
    clean build 2>&1 | tee "$REPO_ROOT/orchestrator/logs/$(date +%F)/_build.log"
  BUILD_RC=${PIPESTATUS[0]}
fi
echo "build rc=$BUILD_RC"
echo ""

# ---------- 2. xcodebuild test ----------
echo "--- [2/3] xcodebuild test ---"
if [ $BUILD_RC -ne 0 ]; then
  echo "!! Build failed, skipping tests."
  TEST_RC=99
else
  xcodebuild \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    -quiet \
    test 2>&1 | tee "$REPO_ROOT/orchestrator/logs/$(date +%F)/_test.log"
  TEST_RC=${PIPESTATUS[0]}
fi
echo "test rc=$TEST_RC"
echo ""

# ---------- 3. SwiftLint ----------
echo "--- [3/3] swiftlint ---"
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --quiet 2>&1 | tee "$REPO_ROOT/orchestrator/logs/$(date +%F)/_lint.log"
  LINT_RC=${PIPESTATUS[0]}
else
  echo "!! swiftlint not installed (brew install swiftlint), skipping."
  LINT_RC=99
fi
echo "lint rc=$LINT_RC"
echo ""

echo "=== validate.sh done at $(date -Iseconds) ==="
echo "summary: build=$BUILD_RC test=$TEST_RC lint=$LINT_RC"

# exit with worst of the three (but 99=skipped doesn't fail)
WORST=0
for rc in $BUILD_RC $TEST_RC $LINT_RC; do
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 99 ]; then
    WORST=$rc
  fi
done
exit $WORST
