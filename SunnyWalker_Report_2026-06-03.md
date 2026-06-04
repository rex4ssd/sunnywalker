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

## 5. 聲控停鬧鐘的最終解法（前景 in-app）

**症狀演進：** 背景聲控（黑標時說話）一直無效，要進主 App 才停得了。

**Root cause（真機 log 證實）：** AlarmKit 鬧鐘響鈴時會 **`AVAudioSession interruption BEGAN`**，把整個 App 的音訊 session 搶走——前景後景都收不到音，`SFSpeechRecognizer` 拿不到 buffer。所以「鬧鐘響的當下用聲音關掉它」在 AlarmKit 下根本做不到。舊版會成功是因為當時走 UNNotification、由 App 自己播聲音、App 握 session 才能邊響邊聽。

**解法：app 在前景時，改由 App 自己叫起床畫面，不靠 AlarmKit 黑標。** `HomeView` 新增每秒前景 watcher `checkForegroundAlarm()`（`guard scenePhase == .active && firingAlarm == nil && AlarmKitService.isAuthorized`，`lastForegroundFiredKey` 防一分鐘內重複）。鬧鐘分鐘一到 → `firingAlarm = alarm` 直接叫 `AlarmRingView`（App 自己的 `AVAudioEngine`/`SpeechRecognizer` 握 session → 爸媽錄音播放 + 聲控都能跑），並 `AlarmKitService.stop(id:)` 停掉系統黑標、`syncAlarm` 重排下次。AlarmRingView 聲控有 5 秒暖機，剛好避開中斷窗口。**真機已驗證：前景說「我起床了」可成功停鬧鐘。**

**Caveat：** AlarmKit 跟 watcher 瞄準同一分鐘，可能有 ≤1 秒黑標/聲音閃一下才被全螢幕蓋掉（無法真正 pre-empt AlarmKit 的排程 fire）。

**檔案：** `Views/Home/HomeView.swift`

---

## 6. 背景聆聽：誠實化 + 省電關閉

既然證實 AlarmKit 授權下背景聲控不可能（session 被搶 + 前景已交給 AlarmRingView），讓 `BackgroundListeningManager.start()` 在 `AlarmKitService.isAuthorized` 時**直接不啟動麥克風**——避免常亮橘點、整夜耗電、kids app 送審紅旗。背景聆聽只保留給 UNNotification fallback（App 自己握 session 才聽得到）。設定頁「背景聆聽模式」說明文案也改成誠實版：「聲控只在 App 起床畫面（前景）有效；系統鬧鐘響時佔麥克風，背景/黑標無法聲控，請按 ✕。」

**定位調整：** 聲控「我起床了」自此定位為 **in-app 起床確認**（播慶祝、記 WakeRecord），不是停鬧鐘的手段。

**檔案：** `Services/AudioRecorder.swift`、`Localizable.xcstrings`

---

## 7. 起床結果音效（慶祝 / 安慰）

- **成功**（`handleWakeUp`，聲控／按鈕／fallback 皆會）→ 播 `success_cheer.wav`（🎉 上行 C 大調琶音 + shimmer + sparkle），接著跳獎勵畫面。
- **逾時沒辨識成功**（`handleAutoStop`，響鈴到 `alarmRingDurationMinutes`）→ 播 `timeout_sad.wav`（😞 溫和下行 D-B-G，music-box 風、刻意不嚇小孩），響完約 1.6 秒再關畫面。

共用 `playEffectOnce(_:)`：用既有 `audioPlayer.play(url:loop:false)` 一次性播放（reuse 同一 player 會自動停掉 looping 鬧鐘音）；找不到檔則 fallback `audioPlayer.stop()` 確保鬧鐘不會繼續響。音檔用 numpy 合成 44.1k/16-bit mono WAV，放 `SunnyWalker/Theme/Sounds/`。

**檔案：** `Views/Alarm/AlarmRingView.swift`、新增 `Theme/Sounds/success_cheer.wav`、`Theme/Sounds/timeout_sad.wav`

---

## 8. Build / 簽署修復

跑 `xcodegen generate`（為了把新音檔收進 bundle）後連環爆，逐一解決：

- **`Ambiguous use of 'init()'`（HomeView + SettingsView）** — 有兩個 `struct SettingsView`：舊的 standalone `Views/Settings/SettingsView.swift`（缺床邊/響鈴時長/背景聆聽）與現役內嵌在 `HomeView.swift` 的。xcodegen 重掃把 orphan 檔加回 target → 同名 type → `SettingsView()` ambiguous。**修法：刪除 standalone 檔。**
- **ConfettiSwiftUI 一堆 `Undefined symbol` + Linker failed** — SPM 套件依賴原本只存在手改的 `.pbxproj`，`project.yml` 沒宣告 → xcodegen 重生時丟掉。**修法：`project.yml` 加 `packages: ConfettiSwiftUI {url, from: 1.1.0}` + target `dependencies: -package`。**（教訓：所有 SPM 依賴必須寫進 project.yml）
- **Bundle ID `com.m2k.*` → 正式 `app.rexcode.*`** — 對照 `IDENTIFIERS.md` 改 `project.yml`：prefix `app.rexcode`、主 App `app.rexcode.sunnywalker`、測試 `app.rexcode.sunnywalkertests`、`DEVELOPMENT_TEAM NHY8MKW8NH`。
- **`No Account for Team` / `No profiles`** — macOS 系統 Apple 帳號 ≠ Xcode 開發者帳號。解法：Xcode → Settings → Accounts 加入 **WU, RUEI-YI** 的 Apple ID（team RUEI YI WU / NHY8MKW8NH，Admin），自動簽署即可抓到 `app.rexcode.sunnywalker` 的 profile（App ID + AlarmKit entitlement 已註冊在此 team）。

**檔案：** `project.yml`、刪除 `Views/Settings/SettingsView.swift`

---

## 變更檔案清單（整輪）

| 檔案 | 內容 |
|---|---|
| `Views/Settings/AlarmEditorView.swift` | 12/24h pickerLocale；Save 鈕移右上 toolbar |
| `Intents/StopAlarmIntent.swift` | StopAlarmIntent 加 log；新增背景型 `DismissAlarmIntent` |
| `Services/AlarmKitService.swift` | `syncAlarm` 依貪睡模式擇一綁 stopIntent |
| `SunnyWalkerApp.swift` | 註冊 `SUNNYWAKE_ALARM` category；`didReceive` 攔 ✕ + 主緒化 + log；`markAlarmDismissed` |
| `Views/Home/HomeView.swift` | ✕ 抑制路由；**前景 watcher `checkForegroundAlarm`**；AlarmSnapshot 帶 strict |
| `Services/AudioRecorder.swift` | AlarmKit 授權時不啟動背景麥克風；中斷 observer 診斷 log；strict 不背景聲控 |
| `Views/Alarm/AlarmRingView.swift` | 成功 cheer / 逾時 sad 音效（`playEffectOnce`） |
| `Localizable.xcstrings` | 補 6 個 key 英文翻譯；背景聆聽說明改誠實版 |
| `Theme/Sounds/success_cheer.wav` ＋ `timeout_sad.wav` | 新增起床結果音效 |
| `project.yml` | Bundle ID → app.rexcode；team；**宣告 ConfettiSwiftUI 套件** |
| ~~`Views/Settings/SettingsView.swift`~~ | **已刪除**（重複 type） |

---

## 已知風險 / 後續

- **跨環境一致性：** 行為取決於 AlarmKit 是否授權。授權 → AlarmKit（黑標=alert）+ 前景 watcher；未授權 → UNNotification fallback + 背景聆聽。改鬧鐘行為前先確認當下走哪條。
- **AlarmKit 佔麥克風是硬限制：** 響鈴中無法做任何語音辨識（已用 `AVAudioSession interruption BEGAN` 證實）。聲控只能在 App 前景的 AlarmRingView 跑。
- **前景 watcher 的 ≤1s 黑標閃爍：** 可接受；若要完全消除需研究能否 pre-empt AlarmKit 排程 fire。
- **簽署只在有 WU RUEI-YI 帳號的 Xcode 上可簽** `app.rexcode.sunnywalker`（Bundle ID 全球唯一綁 team NHY8MKW8NH）。
- **上架前：** `MARKETING_VERSION` 目前 `0.1.0`，IDENTIFIERS 寫上架版本 `1.0`，archive 前記得改。
- **stop 按鈕文案：** AlarmKit alert 的「我起床了」鈕在非貪睡模式現在只是關閉，語意略有落差，未來可依模式給不同文案。

---

*本報告對應之決策與踩雷已寫入 Vein lore（tag `project:sunnywalker`）。*
