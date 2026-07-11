Hello,

Thank you for your patience. We found the root cause, and it was a bug on our side. We have fixed it in build 15, which we have just submitted.

What happened: SunnyWalker offers a free lifetime unlock ("grandfather") to users who first downloaded the app before we introduced the paid Pro tier. That check reads AppTransaction.originalAppVersion. In the App Review / sandbox environment this value is always reported as "1.0", so on the review device the app incorrectly classified the reviewer as an early free-era user and automatically unlocked Pro. That is why the Settings screen showed a static "Pro unlocked" row instead of the purchase row with the localized price - the purchase entry and the price were hidden precisely because the app believed Pro was already owned.

In build 15 the grandfather grant is only applied when the app transaction environment is Production, so the review environment now shows the normal purchase flow.

How to locate SunnyWalker Pro in build 15:

1. On the main screen, tap the gear (Settings) button at the bottom-right.
2. A parental gate appears with a 3-digit multiplication question. Select the correct answer to proceed (this quiet, gated placement follows the Kids Category requirements of Guideline 1.3 - no promotion is shown to children anywhere in the app).
3. In Settings, scroll to the bottom. The "SunnyWalker Pro" row now appears with the localized price (fetched from the App Store via StoreKit). Tapping it opens the purchase screen with the localized price on the buy button, plus a Restore Purchases option.

To answer the question from Guideline 2.1 directly: users purchase the Pro version through that Settings row. It is a single non-consumable In-App Purchase (product ID: app.rexcode.sunnywalker.pro.lifetime) that permanently removes the free-tier limits: unlimited alarms (free tier is capped at 10), unlimited custom ringtones (free tier capped at 5), and ringtone length up to 30 seconds (free tier is 5 seconds).

We have attached screenshots of the parental gate, the Pro row in Settings, and the purchase screen. Please let us know if any further information would help.

Thank you.
