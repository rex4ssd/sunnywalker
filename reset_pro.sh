#!/usr/bin/env bash
# SunnyWalker — reset Pro/grandfather state on the booted simulator so the app
# goes back to the un-purchased free tier (lets you see the purchase button again).
#
#   ./reset_pro.sh            # clear flags on the running ("booted") simulator
#   ./reset_pro.sh <UDID>     # target a specific simulator instead of "booted"
#
# Why: the grandfather grant is sticky by design. Once StoreService writes
# proGrandfathered=true (or a purchase sets isProUnlocked=true), it persists in the
# app's UserDefaults across relaunches AND across code changes — so a rebuild alone
# won't un-Pro you. This wipes those three keys.
#
# Reminder after running this:
#   • In StoreKit local testing, originalAppVersion defaults to "1.0" (< firstPaidBuild 11),
#     so a fresh launch RE-grandfathers you — clearing flags alone loops back to Unlocked.
#   • To get the PURCHASE button: Edit Scheme → Run → Arguments → Environment Variables →
#     add  SW_FORCE_NEW_USER = 1  (DEBUG-only test lever), then ./reset_pro.sh and ⌘R.
#     Remove the env var to test the grandfather (free-Pro) path again.
#   • Watch the Xcode console on launch:
#       🧪 SW_FORCE_NEW_USER=1 …  → new code, forced new user (buy button)
#       🎁 …originalAppVersion=…  → new code, grandfathered
#       (no such line)            → OLD binary still installed; you didn't ⌘R the app

set -euo pipefail

BUNDLE_ID="app.rexcode.sunnywalker"
TARGET="${1:-booted}"
KEYS=(proGrandfathered proEntitlementResolved isProUnlocked)

echo "▶︎ Resetting Pro state for ${BUNDLE_ID} on simulator: ${TARGET}"
for key in "${KEYS[@]}"; do
  # `defaults delete` errors if the key is absent — that's fine, treat as already-clear.
  if xcrun simctl spawn "$TARGET" defaults delete "$BUNDLE_ID" "$key" 2>/dev/null; then
    echo "  ✓ deleted $key"
  else
    echo "  · $key not set (ok)"
  fi
done

echo
echo "✅ Pro flags cleared. Now ⌘R (rebuild & reinstall) to relaunch with a clean entitlement."
echo "   If you still land on Pro, originalAppVersion in StoreKit testing is < 11 → set it to 13"
echo "   in SunnyWalker/Configuration.storekit (App Transaction) to test the purchase flow."
