#!/usr/bin/env bash
# scripts/git_ca.sh — safe git commit & push helper for AI C (Reporter)
# Usage:  bash scripts/git_ca.sh "Day 3: AlarmScheduler done  [A:✅ B:⚠️]"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MSG="${1:?usage: git_ca.sh \"<commit message>\"}"
SAFE_BRANCH="dev/auto"
PROTECTED="main"

# 1. Refuse to run on protected branch — switch to dev/auto
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" = "$PROTECTED" ]; then
  echo "!! On $PROTECTED. Switching to $SAFE_BRANCH..."
  if git show-ref --verify --quiet "refs/heads/$SAFE_BRANCH"; then
    git switch "$SAFE_BRANCH"
  else
    git switch -c "$SAFE_BRANCH"
  fi
fi

# 2. Check there's something to commit
if git diff --cached --quiet && git diff --quiet; then
  echo "!! Nothing to commit. Exiting."
  exit 0
fi

# 3. Stage everything
git add -A

# 4. Show what's being committed
echo "--- staged changes ---"
git diff --cached --stat
echo "----------------------"

# 5. Commit (no amend, no force)
git commit -m "$MSG"
SHA=$(git rev-parse --short HEAD)
echo "committed $SHA"

# 6. Push (only to dev/auto)
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" != "$SAFE_BRANCH" ]; then
  echo "!! Refusing to push: current branch is $CURRENT, expected $SAFE_BRANCH"
  exit 2
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push origin "$SAFE_BRANCH" 2>&1 || {
    echo "!! Push failed (likely no upstream). Setting upstream..."
    git push -u origin "$SAFE_BRANCH"
  }
else
  echo "!! No 'origin' remote configured. Skipping push."
fi

echo "done: $SHA on $SAFE_BRANCH"
