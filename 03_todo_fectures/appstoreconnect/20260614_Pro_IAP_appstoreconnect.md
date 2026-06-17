# App Store Connect 內容 — SunnyWalker Pro IAP（原 1.3.20260614 build 11 → 實際隨 1.3.20260615 build 14 送審）

> 🛑 **build 11 已放棄；IAP 最終隨 build 14（1.3.20260615）送審，定價改為 US$1.99 base（台灣約 NT$60）。** 下表 Price 已更新；其餘設定（Product ID、Family Sharing 等）不變。
> 配合 release：`release_note/apple_store.md` 的 1.3.20260615 (build 14) 段。
> App：SunnyWalker · Bundle `app.rexcode.sunnywalker` · ASC App ID `6775802674` · Team `NHY8MKW8NH`
> 類別：Education（**Made for Kids**，6–8）· App Privacy：Data Not Collected · Privacy Policy：https://rexcode.app/sunny_walker/privacy/

---

## 1. In-App Purchase 設定（ASC → 功能 → App 內購買項目）

| 欄位 | 值 |
|---|---|
| Type | **Non-Consumable**（一次買斷、永久） |
| Reference Name | `SunnyWalker Pro Lifetime`（後台用，不對外） |
| Product ID | `app.rexcode.sunnywalker.pro.lifetime`（**須與程式 / `.storekit` 完全一致**） |
| Price | **US$1.99（base 美國，Apple 標準價格點）** — 其餘 storefront 由 Apple 換算，台灣約 NT$60（舊規劃 NT$50／NT$90／NT$120 皆作廢） |
| Family Sharing | **開啟**（程式 `familyShareable: true`） |
| Cleared for Sale | 是 |

### 顯示名稱 / 說明（Localizations，兩語都要填）

**zh-TW**
- Display Name：`SunnyWalker Pro`
- Description：`終身解鎖：鬧鐘數量、自定鈴聲數量與長度、錄音長度全部無上限。一次購買，永久使用。`

**en-US**
- Display Name：`SunnyWalker Pro`
- Description：`Lifetime unlock: unlimited alarms, unlimited voice clips, longer recordings. One-time purchase, yours forever.`

### IAP 審核資料
- **Review Screenshot（必填）**：在真機/模擬器截 `ProUpgradeView` 購買頁（要看得到品名 + 價格 + 購買鍵 + Restore）。
- **Review Notes（IAP 欄位）**：見下方第 4 節，可直接複用。
- ⚠️ **第一次送 IAP 必須「與 binary（build 11）一起送審」** —— 在版本頁的「App 內購買項目」區把這個 IAP 勾進本次送審，否則 IAP 不會被審。

---

## 2. App Store 商店頁文字

### What's New（版本說明）
> 已放在 `release_note/apple_store.md`（zh-Hant + en）。複製貼上即可。

### Subtitle（副標，30 字元內）
- 現在是 **Made for Kids**，可使用「孩子 / kids」字眼（2026-06-09 那次 2.3.8 退件是因為「當時非 Kids 類別卻用 for kids」，現已是 Kids 類別，無此問題）。
- 沿用前版副標即可；若要呼應 Pro，可選填：
  - zh：`爸媽的聲音當鬧鈴`
  - en：`Wake them with your voice`

### Promotional Text（≤170 字元，可隨時改、不需重審）
- zh：`SunnyWalker Pro 上線：一次買斷，鬧鐘與錄音全部無上限。老用戶更新即免費升級。基本功能永遠免費、完全離線、零廣告。`
- en：`SunnyWalker Pro is here: one-time unlock for unlimited alarms & recordings. Existing users upgrade free. Core features always free, fully offline, zero ads.`

### Description（完整商店描述，加入 Pro 段落；其餘沿用前版）

**zh-Hant**
```
SunnyWalker 是一款專為小朋友設計的暖心鬧鐘。

‧ 爸媽可以錄下自己的聲音，溫柔地把孩子叫醒
‧ 鎖屏、靜音也照響，不錯過上學時間
‧ 孩子說出「我起床了」就能關掉鬧鐘，養成自己起床的習慣
‧ 起床後有可愛的獎勵動畫，讓早晨變得期待

— SunnyWalker Pro（選購）—
一次購買、永久解鎖，並支援家庭共享：
‧ 無限鬧鐘（免費版 6 個）
‧ 無限自定鈴聲（免費版 5 段）
‧ 更長的自定鈴聲（30 秒，免費版 5 秒）
‧ 更長的家長錄音（免費版 3 分鐘）
升級入口在「設定」裡的家長驗證之後，孩子不會誤觸購買。

100% 離線、無廣告、不收集任何資料，錄音只留在你的裝置裡。
```

**English (en)**
```
SunnyWalker is a gentle wake-up alarm made for young children.

• Parents can record their own voice to wake their child up warmly
• Rings even on the Lock Screen and in Silent mode, so school mornings stay on time
• The child says "I'm awake" to turn the alarm off, building a healthy wake-up habit
• A cheerful reward animation makes mornings something to look forward to

— SunnyWalker Pro (optional) —
A one-time purchase that unlocks everything forever, with Family Sharing:
• Unlimited alarms (6 on the free tier)
• Unlimited saved voice clips (5 on the free tier)
• Longer custom clips (30s, up from 5s)
• Longer parent recordings (up from 3 minutes)
The upgrade lives in Settings behind a parental gate, so kids can't tap to buy.

100% offline, no ads, and no data collected — recordings stay on your device.
```

### Keywords（100 字元內，沿用前版基礎可調；建議）
```
鬧鐘,兒童,起床,親子,錄音,叫醒,小孩,習慣,alarm,kids,wake up,parent,routine,morning
```
> 若 `docs/for_Apple_store/20260612_appstoreconnect_content.md` 已有定稿 keywords，以該檔為準，本次不必改。

---

## 3. App Review Notes（貼到版本頁的「App 審查資訊 → 備註」）

```
This update adds one non-consumable in-app purchase, "SunnyWalker Pro"
(app.rexcode.sunnywalker.pro.lifetime) — a one-time lifetime unlock that raises
the free-tier limits (number of alarms, number of saved voice clips, voice-clip
length, and parent-recording length). Family Sharing is enabled.

SunnyWalker is a Made for Kids app, so the purchase is gated behind a parental
gate, per the Kids category requirements:

  1. On the main screen, tap the Settings (gear) button.
  2. A parental gate appears first — solve the challenge (an adult task that
     children cannot complete by guessing).
  3. After the gate, tap "SunnyWalker Pro" to open the purchase sheet.
  4. "Restore Purchases" is available on the same sheet.

There is NO way to reach the purchase without passing the parental gate.

Testing note: a clean install shows the paywall as expected. Devices that
previously ran SunnyWalker are granted Pro automatically (a free goodwill grant
to existing users) — this does not affect a clean-install review.

Privacy: the app collects no data, has no third-party analytics and no
advertising. All microphone and speech processing happens on-device.
COPPA-compliant privacy policy: https://rexcode.app/sunny_walker/privacy/
```

---

## 4. 送審前最終確認（後台 + binary）

- [ ] IAP 已建立、Cleared for Sale、Family Sharing on、兩語 localization 齊、Review Screenshot 已上傳
- [ ] 版本頁「App 內購買項目」把此 IAP **勾進本次送審**（與 build 11 一起）
- [ ] 版本頁貼上 What's New（中/英）、Promotional Text、Description（含 Pro 段）
- [ ] Age Rating = Made for Kids（6–8）；App Privacy = Data Not Collected；Privacy Policy URL 已填
- [ ] Review Notes（第 3 節）已貼，家長驗證步驟清楚
- [ ] binary：build 11、`MARKETING_VERSION 1.3.20260614`、`xcodegen generate` 後 Archive 上傳
- [ ] 真機 sandbox 帳號實測一次完整購買 + Restore；StoreKit Transaction Manager 測退款 → 上限回鎖
- [ ] Submit for Review（Made for Kids 更新 + 首個 IAP，皆需人工審核，不會自動發佈）
