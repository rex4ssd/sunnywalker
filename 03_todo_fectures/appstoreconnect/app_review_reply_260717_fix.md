# App Review 被拒修正單（260717）— v2（發現 IAP 型別建錯，砍掉重建）

- 被拒條款：Guideline 2.1(b) - App Completeness——「IAP 商品未送審」＋「送審 IAP 必須先提供 App Review screenshot」。
- **v2 更新（看過 ASC 截圖後）**：問題比缺截圖嚴重——**商品被建成 Consumable（消耗型），必須刪掉重建**。

---

## 好消息（不變）

這次退件完全沒再提「找不到 Pro / 找不到價格」→ **build 15 的 sandbox grandfather 修正已過關**。

## 根因（兩層）

1. **表層（退件點名的）**：IAP 的 Review Screenshot 欄空 → 商品卡在 Prepare for Submission → 沒進審查隊列。
2. **深層（截圖發現的，致命）**：ASC 商品 **Type = Consumable**，但 code 是 Non-Consumable 語意
   （`Transaction.currentEntitlements` 持久解鎖 + Family Sharing + Restore）。消耗型交易 `finish()`
   後**不會**留在 currentEntitlements——照這樣上架：**使用者付錢 → 下次開 app Pro 消失、Restore 無效**。
   消耗型也不支援 Family Sharing（商店文案承諾了家庭共享）。
   - IAP **型別建立後不可改** → 只能刪掉重建。
   - **刪除的 Product ID 會被鎖、不可重用** → 新商品要用新 ID。

## Code 已改好（2026-07-17，commit `1f21fff`，hotfix/1.3-b15）

- Product ID：`app.rexcode.sunnywalker.pro.lifetime` → **`app.rexcode.sunnywalker.pro.lifetime2`**
  （StoreService.swift + Configuration.storekit；.storekit 本來就是 NonConsumable + familyShareable）
- build 15 → **16**（換 ID 需新 binary；Apple 退件本來也要求 upload a new binary）
- 測試全綠。main 也已同步（product ID + build 17）。
- ⚠️ 注意：build 16 會帶上 hotfix 分支 07-09 以後的 13 個 commit（i18n 修正、共用庫
  ParentalGate/LanguageStore/FamilyShelf/ReviewPrompt/AudioCoreKit、About 版號區塊）。
  多半在家長閘之後、無新權限，風險可控，但不再是「最小 diff」——送審前自己過一次 app。

---

## ASC 操作順序（跟 code 無關的都在網頁上做）

### Step 1 — 刪掉建錯的 Consumable 商品

營利 → App 內購買項目 → `SunnyWalker Pro Lifetime`（Consumable 那顆）→ 刪除。
（從未送審、從未上架、無人購買——可安全刪除。）

### Step 2 — 重建 Non-Consumable 商品（欄位值照抄）

| 欄位 | 值 |
|---|---|
| **Type** | **Non-Consumable ⚠️（這次務必選對，建立後不可改）** |
| Reference Name | `SunnyWalker Pro Lifetime` |
| Product ID | `app.rexcode.sunnywalker.pro.lifetime2`（**與 build 16 的 code 一致，一字不差**） |
| Price | US$1.99（base 美國） |
| Availability | 所有國家/地區 |
| **Family Sharing** | **開啟**（Non-Consumable 才有這個選項——看到它=型別選對了） |

**Localizations**（IAP 的 Display Name ≤30 字元、Description ≤45 字元，超過會被截斷）：

- zh-TW：Display Name `SunnyWalker Pro`；Description `終身解鎖：鬧鐘、鈴聲、錄音全部無上限。一次購買永久使用。`
- en-US：Display Name `SunnyWalker Pro`；Description `Lifetime unlock: unlimited alarms & clips.`

**Review Information：**

- Screenshot：購買頁（ProUpgradeView）截圖——上次回信的「截圖 3」直接重用（尺寸寬鬆 320–3840px）。
- Review Notes：貼下方〔IAP Review Notes〕。

存檔後狀態應為 **Ready to Submit**（不是就還有欄位沒補）。

### Step 3 — Archive & Upload build 16

```bash
cd ~/Documents/SunnyWalker && git switch hotfix/1.3-b15   # commit 1f21fff
open SunnyWalker.xcodeproj
# Any iOS Device → Product → Archive → 確認 1.3.20260615 (16) → Distribute → Upload
```

### Step 4 — 版本頁

1. Build 區塊：移除 build 15 → 掛 **build 16**（等處理完）。
2. **「App 內購買項目」區塊：把新的 lifetime2 商品加進來**（上次就是漏了這步）。
3. 商店 Description：免費版鬧鐘 **6 → 10**（zh：「免費版 6 個」→「免費版 10 個」；en：「(6 on the free tier)」→「(10 on the free tier)」）。
4. 版本 Review Notes：換成下方〔版本 Review Notes〕。

### Step 5 — 回信（下方草稿）→ Submit for Review

---

## 〔IAP Review Notes〕（新商品的 Review Notes 欄）

```
SunnyWalker Pro is a one-time, non-consumable lifetime unlock that removes the
free-tier limits (number of alarms, saved voice clips, clip length, and parent
recording length). Family Sharing is enabled.

How to locate it in the app: on the main screen tap the gear (Settings) button,
pass the parental gate (a multiplication question - a Kids Category requirement,
Guideline 1.3), then scroll to the bottom of Settings and tap the "SunnyWalker
Pro" row, which shows the localized price and opens this purchase sheet. A
"Restore Purchases" option is on the same sheet.
```

## 〔版本 Review Notes〕（版本頁「App 審查資訊 → 備註」，整段取代舊文）

```
This version offers one non-consumable in-app purchase, "SunnyWalker Pro"
(app.rexcode.sunnywalker.pro.lifetime2) - a one-time lifetime unlock that
raises the free-tier limits (number of alarms, number of saved voice clips,
voice-clip length, and parent-recording length). Family Sharing is enabled.

SunnyWalker is a Made for Kids app, so the purchase is gated behind a parental
gate, per the Kids category requirements:

  1. On the main screen, tap the Settings (gear) button.
  2. A parental gate appears - a multiplication question that children cannot
     pass by guessing. Select the correct answer.
  3. In Settings, scroll to the bottom and tap "SunnyWalker Pro" (the row shows
     the localized price) to open the purchase sheet.
  4. "Restore Purchases" is available on the same sheet.

There is NO way to reach the purchase without passing the parental gate.

Note on early adopters: users whose Apple ID first downloaded SunnyWalker while
it was fully free receive the Pro unlock at no charge. This grant only applies
in the production environment, so a review-environment install always shows the
normal purchase flow with the localized price.

Privacy: the app collects no data, has no third-party analytics and no
advertising. All microphone and speech processing happens on-device.
COPPA-compliant privacy policy: https://rexcode.app/sunny_walker/privacy/
```

## 回信草稿（App Review 訊息串，純 ASCII）

```
Hello,

Thank you for the review. We have completed the In-App Purchase submission,
and while doing so we also corrected a configuration mistake on our side:

1. The original In-App Purchase product had been created with the wrong type
(consumable). We removed it and created the correct non-consumable product,
"SunnyWalker Pro" (product ID: app.rexcode.sunnywalker.pro.lifetime2), with
complete metadata including the required App Review screenshot. Its status is
Ready to Submit and it is attached to this version's submission.

2. Because the product ID changed, we uploaded a new binary (build 16) that
references the new product.

To locate the purchase in the app: on the main screen tap the gear (Settings)
button, pass the parental gate (a multiplication question, per the Kids
Category requirements), then scroll to the bottom of Settings and tap the
"SunnyWalker Pro" row, which shows the localized price.

Please let us know if anything else is needed.

Thank you.
```

---

## 完成檢查

- [ ] 舊 Consumable 商品已刪除
- [ ] 新商品 Type = **Non-Consumable**、ID = `...pro.lifetime2`、Family Sharing ON、價 $1.99
- [ ] 兩語 localization 已填（en ≤45 字元版本）
- [ ] Review Screenshot 已上傳、IAP Review Notes 已貼 → 狀態 **Ready to Submit**
- [ ] build 16 已上傳、版本頁已掛 build 16
- [ ] 版本頁「App 內購買項目」掛著新商品
- [ ] Description 免費版鬧鐘 6 → 10（zh + en）
- [ ] 版本 Review Notes 已換新
- [ ] 回信已貼 → Submit for Review
- [ ]（過審後）真機用正式 Apple ID sandbox 測一次購買 + Restore + 家庭共享
