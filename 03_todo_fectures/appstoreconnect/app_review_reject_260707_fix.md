# App Review 被拒修正單（260707）

- Submission ID：0ff0f2b5-4393-4b89-be3a-adfb4a8da1b5
- Review date：July 07, 2026
- Review Device：iPad Air 11-inch (M3)
- Version reviewed：1.3.20260615 (14)
- 被拒條款：Guideline 2.3（still unable to locate SunnyWalker Pro）＋ Guideline 2.1（How do users purchase? unable to locate the 'localize price'）
- 性質：**這次不是回信能解的，是我們的 code bug——必須出新 build。**

---

## 根因（一個 bug 解釋兩條退件）

**App Review 跑在 sandbox 環境，而 `AppTransaction.originalAppVersion` 在 sandbox 永遠回傳 `"1.0"`**（Apple 官方文件明載：*"In the sandbox environment, the value of this property is always 1.0"*）。

於是在審查員的裝置上，`StoreService.resolveGrandfatherIfNeeded()`（`SunnyWalker/Services/StoreService.swift`）走到：

```
originalAppVersion = "1.0"
→ leadingInt("1.0") = 1
→ 1 < firstPaidBuild(11)
→ 判定 grandfather ✅ → 免費終身 Pro，sticky 寫入 UserDefaults
```

審查員的 app **一啟動就自動變成 Pro 已解鎖**。接著：

- 設定頁最後一個 section 走 `store.isPro == true` 分支 → 只顯示**靜態「已解鎖」列**（`HomeView.swift:1387`，刻意無購買控制、無價格——Apple 規定已購用戶不能再看到購買鈕）。
- 所以 reviewer 照我們 06-27 回信的步驟：過家長閘 → 捲到設定頁最底 → **看到的是「已解鎖」，不是「SunnyWalker Pro ＋ 價格」**。
- → 2.3「still unable to locate SunnyWalker Pro」＋ 2.1「unable to locate the 'localize price'」，兩條都成立，reviewer 沒有做錯任何事。

> 06-27 fix 檔第 48 行的假設「審查用的測試帳號通常不會是舊用戶，應該看得到購買鈕」就是這次的盲點：
> 帳號新舊無關——**sandbox 環境下 originalAppVersion 根本不帶真實資訊，人人都會被判成 build 1 的舊用戶**。
> 同理：TestFlight 測試者也全部被誤判成 grandfather（一直沒發現，因為測試者看到「已解鎖」不會回報）。

---

## 修法（code fix，出 build 15）

### 1) `StoreService.resolveGrandfatherIfNeeded()`：只在 production 環境授予 grandfather

`AppTransaction.environment`（iOS 16+，我們 target iOS 26 沒問題）能區分 `.production` / `.sandbox` / `.xcode`。
**grandfather 判定只信 production 的 originalAppVersion**；sandbox / xcode 一律不授予、**也不 freeze**（不寫 `resolvedKey`），理由：

- 不授予 → 審查員 / TestFlight 測試者看到正常的購買 UI（價格、購買鈕）。
- 不 freeze → 邊緣情境安全：真的免費期老用戶若裝過 TestFlight build（sandbox），不會被永久凍結成「paid-era」；等他裝回 App Store 正式版（production）時會重新解析、正確拿回 grandfather。

`case .verified(let appTx):` 分支開頭加：

```swift
case .verified(let appTx):
    // Sandbox / Xcode 環境的 originalAppVersion 恆為 "1.0"（Apple 文件明載），
    // 不帶真實安裝歷史 → 絕不能拿來判 grandfather（App Review 就是 sandbox：
    // 26-07-07 被拒即因 reviewer 裝置被誤判成免費期老用戶、自動解鎖 Pro，
    // 導致找不到購買入口與價格）。不授予、也不 freeze——真老用戶回到
    // production 正式版時會重新解析拿回資格。
    guard appTx.environment == .production else {
        proLog("🛒[Pro] AppTransaction env=\(appTx.environment) ≠ production → skip grandfather (originalAppVersion is meaningless here)")
        return
    }
    var raw = appTx.originalAppVersion
    ...（原邏輯不動）
```

注意：

- `#if DEBUG` 的 `SW_FORCE_NEW_USER` / `SW_FAKE_ORIGINAL_BUILD` 測試桿在 guard **之前/之後的取捨**：
  `SW_FORCE_NEW_USER` 在函式更早處已 return，不受影響；
  `SW_FAKE_ORIGINAL_BUILD`（測 grandfather path 用）會被這個 guard 擋掉（dev 跑的是 `.xcode` 環境），
  所以 DEBUG 下 guard 要放寬：`appTx.environment == .production || ProcessInfo…["SW_FAKE_ORIGINAL_BUILD"] != nil`
  （或等價寫法），讓本機還能測 grandfather 路徑。Release 行為不變：只信 production。
- 已上線正式用戶不受影響：production 裝置的 originalAppVersion 是真值，該拿到 grandfather 的照拿；
  已 sticky 授予的（`grandfatheredKey=true`）函式開頭就 return，不會被收回。

### 2) 抽純函式 + 單元測試

把判定抽成可測的純函式（放 `StoreService`，跟 `isGrandfatheredOriginalVersion` 並列）：

```swift
/// 純函式：只有 production 環境的 originalAppVersion 可信。
nonisolated static func shouldGrandfather(originalAppVersion: String,
                                          isProductionEnvironment: Bool) -> Bool {
    guard isProductionEnvironment else { return false }
    return isGrandfatheredOriginalVersion(originalAppVersion)
}
```

新增測試（`SunnyWalkerTests`）：

- `shouldGrandfather("1.0", isProduction: false) == false`（← 這次被拒的精確情境）
- `shouldGrandfather("1.0", isProduction: true) == true`（真・build 1 老用戶）
- `shouldGrandfather("10", true) == true`、`("11", true) == false`、`("14", true) == false`
- `shouldGrandfather("garbage", true) == false`（既有 fail-safe 不變）

### 3) 送審策略：hotfix 分支最小修正，**不要**把 1.4 train 一起上

現況：三次退件（06-18 / 06-27 / 07-07）退的都是同一顆 binary **build 14**（1.3 train，
archive 點 ≈ `1fb2e25`）。但 main 已經走到 **1.4.20260622**：多人分組鬧鐘、吉祥物、
自訂花心「照片」、報時/待辦模式、響鈴診斷……build 14 之後 ~12 個 commit、27 檔 +3,759 行，
全部沒送審過。

**這次只上 grandfather 修正，理由：**

- 這個 submission 已連退三次，reviewer 盯得緊。最小 diff + 回信「build 15 修了這個 bug」
  故事最乾淨，reviewer 好驗證、過件最快。
- 1.4 一起上 = 開新戰場：Kids Category 下「自訂照片」（相簿存取）、多人分組等新功能
  會引來全新的審查面（privacy / 1.3 / 5.1.4），metadata 也得跟著改（又是 2.3 風險）。
- 響鈴診斷是我們自己收 iPad 10 資料的除錯工具，還在收資料階段，不急著進 store build。
- 1.4 之後自己開新版本送審：metadata / 截圖一次補齊多人功能，審查故事乾淨。

**操作：**

```bash
git switch -c hotfix/1.3-b15 1fb2e25     # 從 build 14 的 archive 點開分支
# 只做：StoreService grandfather 環境修正 + shouldGrandfather 純函式 + 單元測試
# project.yml：MARKETING_VERSION 維持 1.3.20260615、CURRENT_PROJECT_VERSION → 15
#（⚠️ 改 project.yml，不是只改 pbxproj——Vein 雷：XcodeGen 會把手改的 pbxproj 蓋回去）
```

- 上傳 build 15 掛回 ASC 同一個版本（version string 維持 1.3.20260615 就不用動版本欄位）。
- 修正 commit 之後 cherry-pick / merge 回 main，讓 1.4 train 也帶著這個修正。
- main 的 `CURRENT_PROJECT_VERSION` 記得改成 16（build 15 被 hotfix 用掉了，
  App Store 拒收重複 build number）。

### 4) 驗證清單（送審前）

- [ ] Xcode StoreKit testing（`.xcode` 環境）：不設任何測試桿 → 設定頁最底應出現「SunnyWalker Pro ＋ 價格」購買列（= reviewer 將看到的畫面）。
- [ ] `SW_FAKE_ORIGINAL_BUILD=5` → 仍能測到 grandfather path（DEBUG 放寬有效）。
- [ ] 全套 `SunnyWalkerTests` 綠（新增的 `shouldGrandfather` 測試含在內）。
- [ ] TestFlight 裝到實機（sandbox）：應顯示購買列與本地化價格——**這就是 review 環境的等價驗證**。
- [ ] App Store Connect：IAP `app.rexcode.sunnywalker.pro.lifetime` 狀態為可送審、且**已附掛在這個版本的 submission**（首個 IAP 必須隨版本一起送）。

---

## App Store Connect 動作

1. 上傳 build 15，掛到同一個 submission。
2. **回覆 reviewer**（純 ASCII 純文字，不用 markdown / 乘號，同 260627 的教訓）↓

---

## 回信草稿（English，貼 App Store Connect）

Hello,

Thank you for your patience. We found the root cause, and it was a bug on our side. We have fixed it in build 15, which we have just submitted.

What happened: SunnyWalker offers a free lifetime unlock ("grandfather") to users who first downloaded the app before we introduced the paid Pro tier. That check reads AppTransaction.originalAppVersion. In the App Review / sandbox environment this value is always reported as "1.0", so on the review device the app incorrectly classified the reviewer as an early free-era user and automatically unlocked Pro. That is why the Settings screen showed a static "Pro unlocked" row instead of the purchase row with the localized price - the purchase entry and the price were hidden precisely because the app believed Pro was already owned.

In build 15 the grandfather grant is only applied when the app transaction environment is Production, so the review environment now shows the normal purchase flow.

How to locate SunnyWalker Pro in build 15:

1. On the main screen, tap the gear (Settings) button at the bottom-right.
2. A parental gate appears with a 3-digit multiplication question. Select the correct answer to proceed (this quiet, gated placement follows the Kids Category requirements of Guideline 1.3 - no promotion is shown to children anywhere in the app).
3. In Settings, scroll to the bottom. The "SunnyWalker Pro" row now appears with the localized price (fetched from the App Store via StoreKit). Tapping it opens the purchase screen with the localized price on the buy button, plus a Restore Purchases option.

To answer the question from Guideline 2.1 directly: users purchase the Pro version through that Settings row. It is a single non-consumable In-App Purchase (product ID: app.rexcode.sunnywalker.pro.lifetime) that permanently removes the free-tier limits: unlimited alarms (free tier is capped at 10), unlimited custom ringtones (free tier capped at 5), and ringtone length up to 30 seconds (free tier is 5 seconds).

We appreciate your thorough review - it uncovered a real bug that would also have affected TestFlight users. Please let us know if any further information would help.

Thank you.

---

## 為什麼不走「移除 metadata 的 Pro 描述」

同 260627 的結論：Pro 是完整實作的真功能（StoreKit 2 + 購買頁 + feature gating + 測試），砍描述是自殘。這次更明確——問題根本不在 metadata，在 grandfather 判定誤傷 sandbox。修 code 才是正解。
