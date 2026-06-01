#!/usr/bin/env bash
# scripts/dev.sh — multipurpose dev helper
# Usage:
#   bash scripts/dev.sh build         # quick xcodebuild
#   bash scripts/dev.sh test          # tests only
#   bash scripts/dev.sh lint          # swiftlint
#   bash scripts/dev.sh sim           # launch simulator + app
#   bash scripts/dev.sh logs          # tail today's orchestrator logs
#   bash scripts/dev.sh clean         # clean derived data
#   bash scripts/dev.sh branch        # ensure dev/auto branch exists

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="SunnyWalker"
DERIVED="$REPO_ROOT/.build"

# Auto-detect an available iPhone simulator (mirrors validate.sh).
# Override by exporting DESTINATION before running, e.g.
#   DESTINATION="platform=iOS Simulator,name=iPhone 17" bash scripts/dev.sh build
if [ -z "${DESTINATION:-}" ]; then
  SIM_NAME=$(xcrun simctl list devices available 2>/dev/null \
    | grep -E "^\s+iPhone" | sed 's/^[[:space:]]*//' | sed 's/ (.*$//' | head -1)
  DESTINATION="platform=iOS Simulator,name=${SIM_NAME:-iPhone 17}"
  echo "auto-detected simulator: $DESTINATION"
fi

CMD="${1:-help}"
shift || true

case "$CMD" in
  build)
    xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED" build
    ;;
  test)
    xcodebuild -scheme "$SCHEME" -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED" test
    ;;
  lint)
    if command -v swiftlint >/dev/null; then
      swiftlint
    else
      echo "swiftlint missing. brew install swiftlint"
    fi
    ;;
  sim)
    # open Simulator and install latest build
    open -a Simulator
    APP_PATH=$(find "$DERIVED" -name "$SCHEME.app" -type d | head -1)
    if [ -n "$APP_PATH" ]; then
      xcrun simctl install booted "$APP_PATH"
      BUNDLE=$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")
      xcrun simctl launch booted "$BUNDLE"
    else
      echo "!! No .app found. Run: bash scripts/dev.sh build"
    fi
    ;;
  logs)
    TODAY="$REPO_ROOT/orchestrator/logs/$(date +%F)"
    if [ -d "$TODAY" ]; then
      ls -la "$TODAY"
      echo "---"
      tail -n 50 "$TODAY"/*.log 2>/dev/null
    else
      echo "no logs for today yet"
    fi
    ;;
  clean)
    rm -rf "$DERIVED"
    echo "cleaned $DERIVED"
    ;;
  branch)
    if git show-ref --verify --quiet refs/heads/dev/auto; then
      echo "dev/auto already exists"
    else
      git switch -c dev/auto
      echo "created dev/auto"
    fi
    ;;
  help|*)
    grep '^#' "$0" | head -20
    ;;
esac
