# SunnyWalker 開發報告 — 2026-06-03

**範圍：** iOS App（SwiftUI / SwiftData / AlarmKit）鬧鐘編輯與響鈴/關閉流程修正，以及英文模式 i18n 殘留中文修補。
**環境：** 真機 iPhone（AlarmKit entitlement **已批准**）、Xcode、iOS 26 路徑。
**本輪共動到 4 個議題、6 個檔案。**

---

## 摘要

本輪處理四件事：

1. 編輯鬧鐘的時間滾輪沒有跟隨 App 的 12/24 時制設定。
2. 「Save Changes」按鈕從畫面底部移到右上角（對著 Cancel）。
3. 非貪睡模式下，按黑標的 ✕ 應「直接關閉鬧鐘」，但實際會打開 App 主視窗並重新跳出鬧鐘畫面。**這項是本輪最關鍵的 bug，經三輪才定位到真正 root cause。**
4. 英文模式下設定頁仍有大量中文（響鈴時長、自動停止時間、背景聲控等）。

其中第 3 項的關鍵轉折：**這台真機的 AlarmKit entitlement 在開發期間被批准了**，導致先前針對 UNNotification 路徑做的修正全部變成「死碼」，黑標實際上是 AlarmKit alert。定位到這點後才一次修對。

---

## 1. 時間滾輪對齊 12/24 時制

**症狀：** App 設定有 `use24HourClock` 開關（HomeView、AlarmListView 都吃這個），但「編輯鬧鐘」的時間滾輪永遠顯示 AM/PM，不跟隨。

**Root cause：** `AlarmEditorView` 的 `DatePicker(.wheel)` 的 12/24h 是由環境 `\.locale` 決定的，而 App 注入的是「UI 語言 locale」（en / zh-Hant），跟使用者的 `use24HourClock` 設定無關，因此滾輪只反映語言預設的時制。

**修法：** 為滾輪覆寫一個 `pickerLocale`，以 UI 語言 locale 為基底、強制 `hourCycle` 對齊設定：

```swift
private var pickerLocale: Locale {
    var components = Locale.Components(locale: localization.locale)
    components.hourCycle = settings.use24HourClock ? .zeroToTwentyThree : .oneToTwelve
    return Locale(components: components)
}
```

再於 `DatePicker` 上 `.environment(\.locale, pickerLocale)`。注入方式（`@ObservedObject AppSettings.shared` / `LocalizationManager.shared`）與既有的 SettingsView 完全一致。

**檔案：** `Views/Settings/AlarmEditorView.swift`

---

## 2. Save 按鈕移到右上角

**需求：** 把底部的大橘色「Save Changes」鈕移到右上角，對著左上角的 Cancel（iOS sheet 標準排版）。

**修法：** 移除 VStack 底部的 `saveButton`，改在 toolbar 加 `.confirmationAction` 項；同時刪掉已無用的 `saveButton` computed property。Cancel 維持 `.cancellationAction`（左上）。

**檔案：** `Views/Settings/AlarmEditorView.swift`

---

## 3. 非貪睡模式 ✕ 直接關閉鬧鐘（本輪重點）

**症狀：** 鬧鐘剛響的黑標，按 ✕ 後 → App 主視窗被打開、鬧鐘畫面（AlarmRingView）又重新跳出來。使用者要的是：非貪睡（requireAppToStop = false）時，✕ 就單純把鬧鐘關掉，不要開 App、不要進起床任務畫面。

這項修了三輪，前兩輪都沒成功，原因是**一開始診斷在錯的路徑上**。以下記錄完整演進，作為 lore。

### 第一輪 — UNNotification 的 dismiss 沒被攔截

最初假設黑標是 `UNNotification`。發現 `SUNNYWAKE_ALARM` category 從未被註冊，導致按 ✕（dismiss）根本不會回呼 delegate。

修法：在 `didFinishLaunching` 用 `setNotificationCategories` 註冊 category 並加 `.customDismissAction`；於 `didReceive` 攔 `UNNotificationDismissActionIdentifier`；payload 帶 `requireAppToStop` 以區分嚴格/非嚴格。

### 第二輪 — 背景執行緒 + 加抑制標記

使用者回報仍失敗。從 log 抓到關鍵警告：

```
Publishing changes from background threads is not allowed; ...
```

`UNUserNotificationCenterDelegate` 在任意（背景）queue 被呼叫，原本 `handleAlarmPayload` 直接在背景緒設 `pendingAlarmID` 並同步 `post .alarmFired`，使 `HomeView.onReceive` 在背景緒改 SwiftUI state；更糟的是 marker 的寫（✕ 清除）與讀（`checkPendingAlarm`）跨執行緒 race，被清掉的 marker 可能被讀成還在 → 鬧鐘又被拉起。

修法：`didReceive` 整段包進 `Task { @MainActor in … }`，所有狀態變更與 `.alarmFired` 都回到 main thread；新增 `dismissedAlarmID` + `dismissedAlarmAt` 的 30 秒短期抑制，`HomeView` 在 `onReceive` 與 `checkPendingAlarm` 路由前都先 `wasRecentlyDismissed()` 檢查並消耗；並補上 `response.actionIdentifier` 的明確 log。

### 第三輪 — 真正的 root cause：AlarmKit 已被授權

使用者回報「狀態一樣，找不到你要的 log」。對照新 log 才發現關鍵：

```
AlarmKitService: authorization → authorized, isAuthorized=true
🔔 AlarmScheduler: AlarmKit authorized — standing down (UNNotification cleared)
```

**這台真機的 AlarmKit entitlement 已被批准。** 一旦 `isAuthorized=true`，`AlarmScheduler` 完全 stand down、不排任何 UNNotification —— 黑標其實是 **AlarmKit alert**，前兩輪所有 UNNotification dismiss 的修正在這台機器上都是死碼（永遠不會被呼叫），這正是 `🔔 didReceive` log 永遠不出現的原因。

AlarmKit 路徑下，stop 按鈕綁的是 `StopAlarmIntent`，其 `supportedModes = .foreground(.immediate)` 且必定 `post .alarmFired` → **不分嚴格與否，一律 foreground 進 AlarmRingView**，這就是「按 ✕ → 開 App + 鬧鐘又跳出」。

**修法：依貪睡模式拆成兩個 intent，排程時擇一綁定**

| 模式 | stopIntent | 行為 |
|---|---|---|
| 貪睡 ON（strict） | `StopAlarmIntent`（foreground） | 開 App + 進 AlarmRingView，讓小孩完成起床任務 |
| 貪睡 OFF（非 strict） | `DismissAlarmIntent`（**`.background`**） | 只 `AlarmManager.stop` + 蓋抑制標記，**不開 App、不進 ring** |

`DismissAlarmIntent` 為新增的背景型 `LiveActivityIntent`；在 `AlarmKitService.syncAlarm`（唯一活路徑；`scheduleAlarm` / `scheduleRecurringAlarm` 已無人呼叫）依 `alarm.effectiveRequireAppToStop` 選擇 stopIntent。兩個 intent 都加了 `⏹️` log。

**驗證（真機，2026-06-03，成功）：**

```
AlarmKitService: scheduling C12E4278 strict(requireAppToStop)=false → stopIntent=DismissAlarmIntent
AlarmKitService: synced C12E4278-… — 18:43, weekdays=[2, 3, 4, 5, 6]
```

非貪睡鬧鐘已正確綁定 `DismissAlarmIntent`，按 ✕ 走背景關閉、不再開 App / 重跳鬧鐘。

**檔案：** `Intents/StopAlarmIntent.swift`、`Services/AlarmKitService.swift`、`SunnyWalkerApp.swift`、`Views/Home/HomeView.swift`、`Services/AlarmScheduler.swift`

> **保留說明：** 第一/二輪的 UNNotification dismiss 修正並未移除 —— 它是 AlarmKit 未授權時的 fallback 路徑，仍然正確且需要保留。

---

## 4. 英文模式 i18n 殘留中文

**症狀：** 切到 English 後，設定頁仍顯示「響鈴時長 / 自動停止時間 / 5 分 / 背景聲控（實驗）/ 背景聆聽模式」等中文。

**Root cause：** 實際渲染的設定頁是 `HomeView.swift` 內嵌的 `SettingsView`。它把中文字面值直接當 `LocalizedStringKey`（與 `language_section` 那種 semantic key 混用），而 `Localizable.xcstrings` 裡這些 key 的 localizations 是空的 → 英文模式 fallback 顯示 key 本身（中文）。

**修法：不改 Swift，只補字串檔。** 在 `Localizable.xcstrings` 補 6 個 key 的 `en` + `zh-Hant`：響鈴時長、自動停止時間、背景聲控（實驗）、背景聆聽模式、兩段說明 footer，以及單位 `%lld 分`。

兩個重點：

- **`Text("\(Int) 分")` 在 runtime 產生的 key 是 `%lld 分`**，而非舊 extract 殘留的 `%@ 分`；兩個都補，且 value 的 placeholder 各自對齊（`%lld→%lld min`、`%@→%@ min`）。
- 刻意用文字 surgical edit 而非整檔 `json.dump` 重寫 —— Xcode 的 key 排序（collation）與空物件格式不同，整檔重寫會炸出約 2500 行假 diff。最終 diff 維持在 **+118 / −5**。

**檔案：** `Localizable.xcstrings`

---

## 變更檔案清單

| 檔案 | 內容 |
|---|---|
| `Views/Settings/AlarmEditorView.swift` | 12/24h pickerLocale；Save 鈕移右上 toolbar |
| `Intents/StopAlarmIntent.swift` | StopAlarmIntent 加 log；新增背景型 `DismissAlarmIntent` |
| `Services/AlarmKitService.swift` | `syncAlarm` 依貪睡模式擇一綁 stopIntent |
| `SunnyWalkerApp.swift` | 註冊 `SUNNYWAKE_ALARM` category；`didReceive` 攔 ✕ + 主緒化 + log；`markAlarmDismissed` |
| `Views/Home/HomeView.swift` | `wasRecentlyDismissed` 抑制；onReceive / checkPendingAlarm 路由前檢查 |
| `Localizable.xcstrings` | 補 6 個 key 的英文翻譯 |

---

## 已知風險 / 後續

- **跨環境一致性：** 行為現在取決於 AlarmKit 是否授權。授權 → 走 AlarmKit（黑標=alert，stopIntent 決定行為）；未授權 → 走 UNNotification fallback。改鬧鐘相關行為前，務必先確認當下走哪條路徑。
- **`IntentModes.background` 待長期觀察：** 真機已驗證非貪睡 ✕ 不開 App，但 AlarmKit 對背景型 stopIntent 的行為仍建議持續關注（OS 版本更新時複測）。
- **stop 按鈕文案：** AlarmKit alert 的 stop 鈕文字為「我起床了」，非貪睡模式現在只是關閉，文案語意略有落差，未來可考慮依模式給不同文案。

---

*本報告對應之決策與踩雷已寫入 Vein lore（tag `project:sunnywalker`）。*
