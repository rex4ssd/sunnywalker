# App Review 被拒修正單（260627）

- Submission ID：0ff0f2b5-4393-4b89-be3a-adfb4a8da1b5
- Review date：June 27, 2026
- Review Device：iPad Air 11-inch (M3)
- Version reviewed：1.3.20260615 (14)
- 類型：Bug Fix Submission

---

## 被拒原因

**Guideline 2.3 - Performance - Accurate Metadata（不準確的中繼資料）**

審查員在 App 內找不到 metadata 中描述的功能，明確點名：**SunnyWalker Pro**。

---

## 查 code 結論：功能是真的有，不要移除描述

`SunnyWalker Pro` 是**完整實作的付費功能**，不是空文案。所以**不該走「移除 Pro 描述」那條路**——那會把一個真功能砍掉。正解是**走選項 A：回信告訴審查員入口在哪**。

證據（程式碼）：

| 項目 | 檔案 |
|---|---|
| StoreKit 2 完整實作（279 行） | `SunnyWalker/Services/StoreService.swift` |
| Pro 購買頁 UI | `SunnyWalker/Views/Settings/ProUpgradeView.swift` |
| Feature gating（鬧鐘/鈴聲上限） | `SunnyWalker/Services/AppSettings.swift` |
| 設定頁 Pro 入口 | `SunnyWalker/Views/Home/HomeView.swift:1352` |
| IAP 商品定義 | `SunnyWalker/Configuration.storekit` |

- IAP Product ID：`app.rexcode.sunnywalker.pro.lifetime`（Non-Consumable，一次購買永久解鎖）
- 解鎖內容：鬧鐘數 10→無限、自定鈴聲 5→無限、單則鈴聲長度 5s→30s
- 還有 grandfather 機制（舊用戶免費升級）與單元測試

---

## 審查員為什麼「找不到」

Pro 入口刻意做得很安靜，藏在「家長閘 + 設定頁最底部」（符合 Made for Kids / Guideline 1.3 的設計）：

1. 主畫面右下角點**齒輪（設定）**鈕。
2. 跳出**家長驗證（Parental Gate）**——一題 3 位數乘法（例：`127 × 4 = ?`），要**選對答案**才會進設定頁。
   - 這很可能就是審查員卡關的點：沒答對乘法題就進不了設定，自然找不到 Pro。
3. 進設定頁後，**往下捲到最底**，倒數第二個 Section 就是「**SunnyWalker Pro**」（右側會顯示價格），點下去即開啟購買頁 `ProUpgradeView`。

> 註：若該 Apple ID 被判定為 grandfather（首次下載 build < 11 的舊用戶），設定頁那一列會顯示「已解鎖」而非購買鈕——審查用的測試帳號通常不會是舊用戶，應該看得到購買鈕。

---

## 需做的動作（選項 A，不需改 build、不需改 metadata）

於 **App Store Connect 回覆此訊息**，說明上面的精確路徑，並附 2 張截圖：
- [ ] 截圖 1：家長驗證乘法題畫面
- [ ] 截圖 2：設定頁最底部「SunnyWalker Pro」那一列（顯示價格）

可直接複製的英文回覆草稿 ↓

---

## 回信草稿（English，純文字，貼到 App Store Connect）

> 註：ASC 的 Reply 框是純文字，不要用反引號 / markdown / 乘號「×」，否則可能跳「An error has occurred」。以下已全部改為純 ASCII，可直接整段貼。

Hello,

Thank you for the review. The SunnyWalker Pro feature is fully implemented in the app as a non-consumable In-App Purchase (product ID: app.rexcode.sunnywalker.pro.lifetime).

A note on our design intent: SunnyWalker is an app for children, and we deliberately chose not to push commercialization at them. For that reason the purchase entry point is intentionally quiet and tucked away. There is no promotional banner, no upsell prompt, and no "limit reached, upgrade now" message anywhere in the app. The only way to reach it is through the parental gate and at the very bottom of the Settings screen, specifically so that a child cannot stumble onto it or tap it by accident. This follows the Kids Category requirements (Guideline 1.3), which is why the feature may not have been immediately visible during review.

Here is how to locate it:

1. On the main screen, tap the gear (Settings) button at the bottom-right.
2. A parental gate appears with a 3-digit multiplication question (for example, "127 x 4 = ?"). Select the correct answer to proceed into Settings.
3. In Settings, scroll to the bottom. The "SunnyWalker Pro" row, showing the localized price, is near the end. Tapping it opens the purchase screen, which offers the lifetime unlock and a "Restore Purchase" option.

Purchasing Pro removes the free-tier limits: unlimited alarms (free tier is capped at 10), unlimited custom ringtones (free tier capped at 5), and longer ringtones up to 30 seconds (free tier is 5 seconds).

We are happy to provide screenshots of the parental gate and the Pro row in Settings if that would help. Please let us know if any further information is needed.

Thank you.
