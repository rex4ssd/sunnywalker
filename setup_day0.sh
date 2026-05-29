#!/usr/bin/env bash
# setup_day0.sh — bootstrap a fresh SunnyWalker iOS project so `sw next` (Day 1) can run.
#
# What this does:
#   1. Verify prerequisites (Xcode, git, xcodegen, optionally gh)
#   2. Write project.yml + minimal Swift skeleton + Info.plist
#   3. Generate SunnyWalker.xcodeproj via xcodegen
#   4. git init + dev/auto branch + initial commit
#   5. (Optional) gh repo create — private
#   6. Reset claude_loop state (ring, approval, cooldown, heartbeat, MAIN_ENTRY)
#   7. Print next steps
#
# Usage:
#   bash setup_day0.sh             # interactive (asks about GitHub)
#   bash setup_day0.sh --no-gh     # skip GitHub repo creation
#   bash setup_day0.sh --skip-xcode # skip Xcode regen (if you already have .xcodeproj)
#   bash setup_day0.sh --reset-only # only wipe claude_loop state, leave Xcode alone

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# ---------- color helpers ----------
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
ok()    { echo "  ${GREEN}✓${RESET} $*"; }
warn()  { echo "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo "  ${RED}✗${RESET} $*" >&2; }
step()  { echo "${BOLD}${BLUE}==> $*${RESET}"; }

# ---------- args ----------
WITH_GH=ask
SKIP_XCODE=0
RESET_ONLY=0
MANUAL_GH=0
for arg in "$@"; do
  case "$arg" in
    --no-gh)       WITH_GH=no ;;
    --gh)          WITH_GH=yes ;;
    --manual-gh)   WITH_GH=no; MANUAL_GH=1 ;;
    --skip-xcode)  SKIP_XCODE=1 ;;
    --reset-only)  RESET_ONLY=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) err "unknown arg: $arg"; exit 1 ;;
  esac
done

# =========================================================
# Reset-only fast path
# =========================================================
if [ $RESET_ONLY -eq 1 ]; then
  step "Reset-only: wiping claude_loop runtime state"
  python3 - <<'PY'
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
print(f"  reset done for {proj['name']}")
PY
  ok 'Run `sw next` to start Day 1.'
  exit 0
fi

# =========================================================
# Step 1: prerequisites
# =========================================================
step "Step 1/7: Checking prerequisites"

command -v xcodebuild >/dev/null 2>&1 || { err "Xcode is required. Install from App Store."; exit 1; }

# Detect "xcode-select pointing to CommandLineTools" — common after fresh Xcode install
XC_DEV=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$XC_DEV" == *"CommandLineTools"* ]]; then
  err "xcode-select is pointing to CommandLineTools, not Xcode."
  echo "      Fix:  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "      Then re-run this script."
  exit 1
fi

# Try xcodebuild -version — fails if Xcode not fully set up
if ! XC_VER_OUT=$(xcodebuild -version 2>&1); then
  err "xcodebuild failed:"
  echo "$XC_VER_OUT" | sed 's/^/      /'
  echo
  echo "      Common causes:"
  echo "      1) Xcode platform packages (iOS SDK) not installed."
  echo "         Open Xcode → it will prompt to install iOS / Simulator runtimes."
  echo "      2) xcode-select pointing at the wrong path."
  echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "      3) License not accepted."
  echo "         sudo xcodebuild -license accept"
  exit 1
fi
XC_VER=$(echo "$XC_VER_OUT" | head -1)
ok "$XC_VER (developer dir: $XC_DEV)"

# Check iOS SDK is actually available
if ! xcodebuild -showsdks 2>/dev/null | grep -q "iphoneos"; then
  err "iOS SDK not installed. Open Xcode and check the 'iOS' platform box, then Install."
  exit 1
fi
ok "iOS SDK present"

command -v git >/dev/null 2>&1 || { err "git required."; exit 1; }
ok "git $(git --version | awk '{print $3}')"

command -v claude >/dev/null 2>&1 || warn "claude CLI not found. Install: npm i -g @anthropic-ai/claude-code"
command -v claude >/dev/null 2>&1 && ok "claude CLI: $(claude --version 2>&1 | head -1)"

if [ $SKIP_XCODE -eq 0 ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    err "xcodegen missing. Install: brew install xcodegen"
    err "(Or rerun with --skip-xcode if you already have an .xcodeproj.)"
    exit 1
  fi
  ok "xcodegen $(xcodegen --version 2>&1 | head -1)"
fi

HAS_GH=0
if command -v gh >/dev/null 2>&1; then
  HAS_GH=1
  ok "gh present (GitHub repo creation available)"
else
  warn "gh CLI not present (GitHub creation will be skipped)"
fi

# =========================================================
# Step 2: write project.yml + Swift skeleton + Info.plist
# =========================================================
if [ $SKIP_XCODE -eq 0 ]; then
  step "Step 2/7: Writing project.yml + Swift skeleton"

  mkdir -p SunnyWalker/Models SunnyWalker/Views SunnyWalker/Theme \
           SunnyWalker/Services SunnyWalker/Assets.xcassets/AppIcon.appiconset

  # project.yml for xcodegen
  cat > project.yml <<'YML'
name: SunnyWalker
options:
  bundleIdPrefix: com.m2k
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: zh-Hant
  groupSortPosition: top
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: 1
    ENABLE_USER_SCRIPT_SANDBOXING: NO
targets:
  SunnyWalker:
    type: application
    platform: iOS
    sources:
      - path: SunnyWalker
    info:
      path: SunnyWalker/Info.plist
      properties:
        CFBundleDisplayName: SunnyWalker
        UILaunchScreen:
          UIColorName: ""
        NSMicrophoneUsageDescription: "鬧鐘需要聽你說「我起床了」才能關掉喔！聲音只留在這台 iPhone 裡，不會傳出去。"
        NSSpeechRecognitionUsageDescription: "用來聽懂你說的話，把鬧鐘關掉。所有辨識都在這台裝置上完成。"
        UIBackgroundModes:
          - audio
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.m2k.sunnywalker
        TARGETED_DEVICE_FAMILY: "1,2"
        GENERATE_INFOPLIST_FILE: NO
  SunnyWalkerTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: SunnyWalkerTests
    dependencies:
      - target: SunnyWalker
YML
  ok "project.yml"

  # App entry
  cat > SunnyWalker/SunnyWalkerApp.swift <<'SWIFT'
// SunnyWalker — SunnyWalkerApp.swift  |  Day 0  |  bootstrap entry point

import SwiftUI

@main
struct SunnyWalkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
SWIFT
  ok "SunnyWalker/SunnyWalkerApp.swift"

  # Root view
  cat > SunnyWalker/ContentView.swift <<'SWIFT'
// SunnyWalker — ContentView.swift  |  Day 0  |  bootstrap root view

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("☀️")
                .font(.system(size: 64))
            Text("SunnyWalker")
                .font(.largeTitle.bold())
            Text("Day 0 — bootstrap complete")
                .foregroundStyle(.secondary)
            Text("AI A will start coding from here on Day 1.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
SWIFT
  ok "SunnyWalker/ContentView.swift"

  # Stub theme so the Ghibli convention is in place from day 1
  cat > SunnyWalker/Theme/GhibliColors.swift <<'SWIFT'
// SunnyWalker — GhibliColors.swift  |  Day 0  |  color tokens (filled by AI A on Day 1)

import SwiftUI

enum GhibliColors {
    // TODO Day 1: fill in spec-defined palette
    static let placeholder = Color.accentColor
}
SWIFT
  ok "SunnyWalker/Theme/GhibliColors.swift (stub)"

  # Minimal test target so `xcodebuild test` doesn't fail on Day 1
  mkdir -p SunnyWalkerTests
  cat > SunnyWalkerTests/SunnyWalkerTests.swift <<'SWIFT'
// SunnyWalker — SunnyWalkerTests.swift  |  Day 0  |  smoke test

import XCTest
@testable import SunnyWalker

final class SunnyWalkerSmokeTests: XCTestCase {
    func testTrueIsTrue() {
        XCTAssertTrue(true, "bootstrap smoke test")
    }
}
SWIFT
  ok "SunnyWalkerTests/SunnyWalkerTests.swift"

  # AppIcon contents stub
  cat > SunnyWalker/Assets.xcassets/Contents.json <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  cat > SunnyWalker/Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  ok "AppIcon stub"

  # =========================================================
  # Step 3: xcodegen
  # =========================================================
  step "Step 3/7: Running xcodegen"
  xcodegen generate 2>&1 | tail -5
  if [ ! -d SunnyWalker.xcodeproj ]; then
    err "xcodegen failed to produce SunnyWalker.xcodeproj"
    exit 1
  fi
  ok "SunnyWalker.xcodeproj generated"
else
  step "Step 2-3/7: Skipped (--skip-xcode)"
fi

# =========================================================
# Step 4: git
# =========================================================
step "Step 4/7: git init + dev/auto branch"

if [ ! -d .git ]; then
  git init -q -b main
  ok "git initialized (main branch)"
else
  ok "git already initialized"
fi

# Ensure .gitignore is sensible
if [ ! -f .gitignore ]; then
  warn ".gitignore missing — should have been created earlier"
fi

# user.name / user.email check (gentle)
if [ -z "$(git config user.email)" ]; then
  warn "git config user.email is empty. Set: git config user.email keep.going@m2k.com.tw"
fi

# Create dev/auto branch if missing
if git show-ref --verify --quiet refs/heads/dev/auto; then
  ok "dev/auto branch exists"
else
  git switch -q -c dev/auto
  ok "dev/auto branch created"
fi

# =========================================================
# Step 5: optional GitHub repo
# =========================================================
step "Step 5/7: GitHub repo (optional)"

if [ $HAS_GH -eq 1 ] && [ "$WITH_GH" != "no" ]; then
  if [ "$WITH_GH" = "ask" ]; then
    echo
    read -r -p "  Create private GitHub repo 'sunnywalker' under your account? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      WITH_GH=no
    else
      WITH_GH=yes
    fi
  fi
  if [ "$WITH_GH" = "yes" ]; then
    if git remote get-url origin >/dev/null 2>&1; then
      warn "git remote 'origin' already set: $(git remote get-url origin)"
    else
      gh repo create sunnywalker --private --source=. --remote=origin \
        --description "Voice-interactive alarm clock for 7-year-olds" \
        --disable-issues --disable-wiki 2>&1 | tail -3 || warn "gh repo create failed (continuing)"
    fi
  fi
else
  warn "Skipping gh repo creation"
  if [ $MANUAL_GH -eq 1 ]; then
    echo
    echo "  Manual GitHub setup (do this in another terminal):"
    echo "  1. Open https://github.com/new"
    echo "  2. Name: sunnywalker  |  Private  |  Don't init README/gitignore/license"
    echo "  3. Back here:"
    echo "       git remote add origin git@github.com:YOUR_USER/sunnywalker.git"
    echo "       git push -u origin dev/auto"
    echo
  fi
fi

# =========================================================
# Step 6: reset claude_loop state
# =========================================================
step "Step 6/7: Reset claude_loop state"
python3 - <<'PY'
import sys, yaml
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))
from orchestrator.lib import ring, schedule, heartbeat, paths, main_entry

# Fresh state — Day 1 will be the first real run
paths.RING.write_text(ring.RING_HEADER)
heartbeat.clear()
schedule.clear_cooldown()
schedule.clear_approval()

# Refresh MAIN_ENTRY with real project metadata
cfg = yaml.safe_load(open('orchestrator/config.yaml'))
proj = cfg['project']
main_entry.write(proj['name'], proj['description'])
print(f"  state reset for {proj['name']}")
PY
ok "ring / approval / cooldown / heartbeat cleared"
ok "MAIN_ENTRY.md refreshed"

# Make sure verbose-logs dir from prior test runs is gone
rm -rf orchestrator/logs/* 2>/dev/null || true
ok "old verbose logs cleared"

# =========================================================
# Step 7: initial commit
# =========================================================
step "Step 7/7: Initial commit"

git add -A
if git diff --cached --quiet; then
  ok "nothing to commit (already clean)"
else
  git commit -q -m "Day 0: bootstrap

- xcodegen project.yml + SunnyWalker.xcodeproj
- minimal SwiftUI skeleton (App + ContentView + GhibliColors stub)
- claude_loop framework with 4-agent ring
- 39-test pytest suite
- schedule.csv / schedule.ini for cooldown + stop_after
- MAIN_ENTRY.md resume manifest"
  ok "committed Day 0 to dev/auto"
fi

# Push if origin set
if git remote get-url origin >/dev/null 2>&1; then
  if git push -u origin dev/auto 2>&1 | tail -3; then
    ok "pushed to origin/dev/auto"
  else
    warn "push failed — you can push manually later"
  fi
fi

# =========================================================
# Done
# =========================================================
echo
echo "${BOLD}${GREEN}========================================${RESET}"
echo "${BOLD}${GREEN}  Day 0 bootstrap complete.${RESET}"
echo "${BOLD}${GREEN}========================================${RESET}"
echo
echo "Next steps:"
echo "  1. ${BOLD}Open Xcode${RESET} and verify it builds:"
echo "       open SunnyWalker.xcodeproj"
echo "       Cmd+B  (should succeed with the bootstrap skeleton)"
echo
echo "  2. ${BOLD}Start the pipeline${RESET}:"
echo "       sw next        # AI A starts Day 1 from the spec"
echo
echo "  3. ${BOLD}Optional cron${RESET} (every 30 min, cooldown-safe):"
echo "       */30 * * * * cd $REPO_ROOT && sw next >> /tmp/sw.log 2>&1"
echo
echo "  4. Inspect: ${BOLD}cat MAIN_ENTRY.md${RESET}  or  ${BOLD}sw status${RESET}"
