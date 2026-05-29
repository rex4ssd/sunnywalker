#!/usr/bin/env bash
# launch.sh — run all remaining bootstrap + verification in one shot.
#
# Captures full output to /tmp/sunnywalker_launch_<timestamp>.log so you can
# paste it back. Prints log path at the end.
#
# Idempotent — safe to re-run. Steps that already passed will be skipped.
#
#   bash launch.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)
LOG=/tmp/sunnywalker_launch_${TS}.log

# Redirect everything (stdout+stderr) to both terminal and log file
exec > >(tee -a "$LOG") 2>&1

# ---------- visual helpers ----------
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
ok()    { echo "  ${GREEN}✓${RESET} $*"; }
warn()  { echo "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo "  ${RED}✗${RESET} $*"; }
step()  { echo; echo "${BOLD}${BLUE}========== $* ==========${RESET}"; }

FAILED_STEPS=()
record_fail() { FAILED_STEPS+=("$1"); }

# ===================================================================
echo "${BOLD}SunnyWalker launch.sh — $(date -Iseconds)${RESET}"
echo "Log: $LOG"
echo "Repo: $REPO_ROOT"
echo "Branch: $(git branch --show-current 2>/dev/null || echo '(no git)')"
echo "Origin: $(git remote get-url origin 2>/dev/null || echo '(no origin)')"

# ===================================================================
step "1/8  Toolchain"

if command -v xcodebuild >/dev/null 2>&1; then
  XC_DEV=$(xcode-select -p 2>/dev/null || echo "")
  if [[ "$XC_DEV" == *"CommandLineTools"* ]]; then
    err "xcode-select points to CommandLineTools, not Xcode"
    err "Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    record_fail "xcode-select"
  else
    ok "$(xcodebuild -version 2>/dev/null | head -1)  (dev dir: $XC_DEV)"
  fi
else
  err "xcodebuild not found"
  record_fail "xcodebuild"
fi

if xcodebuild -showsdks 2>/dev/null | grep -q "iphoneos"; then
  ok "iOS SDK installed"
else
  err "iOS SDK missing — open Xcode and install iOS platform"
  record_fail "ios-sdk"
fi

if command -v xcodegen >/dev/null 2>&1; then
  ok "xcodegen $(xcodegen --version 2>&1 | head -1)"
else
  err "xcodegen missing — brew install xcodegen"
  record_fail "xcodegen"
fi

if command -v claude >/dev/null 2>&1; then
  ok "claude CLI present"
else
  warn "claude CLI not in PATH (npm i -g @anthropic-ai/claude-code)"
fi

if command -v python3 >/dev/null 2>&1; then
  ok "python $(python3 --version 2>&1)"
else
  err "python3 missing"
  record_fail "python3"
fi

# Stop early if toolchain broken
if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
  step "Halt — toolchain incomplete"
  echo "Failed: ${FAILED_STEPS[*]}"
  echo "Fix the above then re-run: bash launch.sh"
  echo "Log: $LOG"
  exit 1
fi

# ===================================================================
step "2/8  Reset claude_loop state (clears TestProject contamination)"

python3 - <<'PY' 2>&1 || record_fail "reset-state"
import sys, yaml
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))
from orchestrator.lib import ring, schedule, heartbeat, paths, main_entry

paths.RING.write_text(ring.RING_HEADER)
heartbeat.clear()
schedule.clear_cooldown()
schedule.clear_approval()

cfg = yaml.safe_load(open('orchestrator/config.yaml'))
proj = cfg['project']
main_entry.write(proj['name'], proj['description'])
print(f"  state reset for {proj['name']}")
PY
ok "ring / approval / cooldown / heartbeat cleared"
ok "MAIN_ENTRY.md regenerated with SunnyWalker metadata"

# ===================================================================
step "3/8  Bootstrap Xcode project (if missing)"

if [ -d SunnyWalker.xcodeproj ]; then
  ok "SunnyWalker.xcodeproj already exists — skipping bootstrap"
else
  bash setup_day0.sh --no-gh --reset-only 2>&1 || true   # state already reset, but harmless
  bash setup_day0.sh --no-gh 2>&1 || record_fail "setup_day0"
  if [ -d SunnyWalker.xcodeproj ]; then
    ok "Xcode project generated"
  else
    err "setup_day0.sh failed to produce .xcodeproj"
  fi
fi

# ===================================================================
step "4/8  xcodebuild — does the skeleton compile?"

if [ -d SunnyWalker.xcodeproj ]; then
  # Pick a simulator destination automatically
  DEST="platform=iOS Simulator,name=iPhone 15"
  if ! xcrun simctl list devices available 2>/dev/null | grep -q "iPhone 15"; then
    # Fallback to any available iPhone
    DEST_NAME=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | head -1 | sed -E 's/.*\(([^)]+)\).*/\1/' || true)
    [ -n "$DEST_NAME" ] && DEST="platform=iOS Simulator,id=$DEST_NAME"
  fi
  echo "  destination: $DEST"

  if xcodebuild -scheme SunnyWalker -destination "$DEST" \
       -derivedDataPath .build -quiet build 2>&1 | tail -20; then
    ok "Build PASSED"
  else
    err "Build FAILED — see lines above"
    record_fail "xcodebuild"
  fi
else
  warn "Skipped — no .xcodeproj yet"
fi

# ===================================================================
step "5/8  pytest — framework self-tests"

if python3 -m pytest tests/ --tb=short -q 2>&1 | tail -10; then
  ok "All pytest tests passed"
else
  err "Some tests failed"
  record_fail "pytest"
fi

# ===================================================================
step "6/8  Sanity: sw status"

if python3 sw.py status 2>&1 | head -30; then
  ok "sw status works"
else
  err "sw status crashed"
  record_fail "sw-status"
fi

# ===================================================================
step "7/8  Git — commit and push to dev/auto"

CURR_BRANCH=$(git branch --show-current)
if [ "$CURR_BRANCH" != "dev/auto" ]; then
  if git show-ref --verify --quiet refs/heads/dev/auto; then
    git switch dev/auto
  else
    git switch -c dev/auto
  fi
  ok "switched to dev/auto"
else
  ok "already on dev/auto"
fi

git add -A
if git diff --cached --quiet; then
  ok "nothing to commit"
else
  git commit -m "Day 0: bootstrap complete (Xcode skeleton + state reset)" -q
  SHA=$(git rev-parse --short HEAD)
  ok "committed $SHA"
fi

if git remote get-url origin >/dev/null 2>&1; then
  if git push origin dev/auto 2>&1; then
    ok "pushed to origin/dev/auto"
  else
    warn "push failed — check above"
  fi
else
  warn "no origin remote configured"
fi

# ===================================================================
step "8/8  Summary"

echo
echo "${BOLD}State files:${RESET}"
ls -la orchestrator/current/ 2>/dev/null | tail -n +2 | sed 's/^/  /'
echo
echo "${BOLD}Xcode project:${RESET}"
ls -la SunnyWalker.xcodeproj 2>/dev/null | head -3 | sed 's/^/  /' || echo "  (missing)"
echo
echo "${BOLD}Recent git log:${RESET}"
git log --oneline -5 | sed 's/^/  /'
echo
echo "${BOLD}MAIN_ENTRY head:${RESET}"
head -20 MAIN_ENTRY.md | sed 's/^/  /'

# ===================================================================
echo
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo "${BOLD}${GREEN}========================================${RESET}"
  echo "${BOLD}${GREEN}  ✅  ALL STEPS PASSED${RESET}"
  echo "${BOLD}${GREEN}========================================${RESET}"
  echo
  echo "Next: ${BOLD}sw next${RESET}    (AI A starts Day 1)"
  echo "Log:  ${LOG}"
  exit 0
else
  echo "${BOLD}${RED}========================================${RESET}"
  echo "${BOLD}${RED}  ❌  FAILED STEPS: ${FAILED_STEPS[*]}${RESET}"
  echo "${BOLD}${RED}========================================${RESET}"
  echo
  echo "Paste this log back: ${LOG}"
  exit 1
fi
