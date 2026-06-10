# SunnyWalker — Snooze（貪睡）實作交接文件

> 給接手的 AI / 工程師。本文件描述「iPhone 內建式 snooze」的目標、試過的做法、為什麼喊停、
> 已確認與待驗證的 AlarmKit API、結構性限制，以及建議的實作步驟。
> 撰寫時間：2026-06-10。撰寫者：Claude（在 Linux 沙箱，**無法編譯 Swift / 無 Xcode**）。
> 環境：iOS 26 AlarmKit、Xcode 26、XcodeGen（`project.yml`）。

---

## 0. 一句話總結

Snooze **目前沒有實作**（試做後已全部還原）。卡點不是「想不到怎麼做」，而是「**做對的關鍵那段程式在最脆弱的排程路徑上、用到我無法編譯驗證的 iOS 26 AlarmKit API**」。本文件把要做的事、確認過的 API、和必須在 Xcode 實機驗證的點全部列清楚，讓下一個有 Xcode 的人能直接接手。

---

## 1. 目標（user 要的行為）

對齊 iPhone 內建時鐘的鬧鐘（鎖屏/背景時的系統警示）：

1. 鬧鐘響時，警示上有「貪睡」按鈕 + 「slide to stop」滑桿。
2. 按「貪睡」→ 暫停，**過 N 分鐘自動再響**。**N 可由家長設定（per-alarm）**。
3. 每一次響鈴，也要依「設定 ▸ 響鈴時長」（現有 `AppSettings.alarmRingDurationMinutes`，1–10 分）**沒人理就自動停**。
4. **最多響幾次**（含第一次）由 SunnyWalker 強制停止：預設 3、範圍 1–10。響滿就不再貪睡再響。
   - 目的：小孩不可控，避免 iPad 整天響到沒電。
5. 只有使用者**橫滑 slide to stop** 才算真正關閉。

截圖參考：iPhone 內建鬧鐘的「Snooze / slide to stop」畫面（user 提供）。

---

## 2. 目前 repo 與 snooze / 貪睡 相關的狀態（2026-06-10）

- **Snooze 從未實作**。曾加過 model 欄位 / 編輯頁 UI / `SnoozeAlarmIntent.swift`，**已全部還原刪除**（避免半成品死 UI）。
- **舊的「貪睡模式」≠ snooze**。專案裡 `requireAppToStop`（strict mode）才是掛「貪睡模式」這個名字的東西，語意是「按 ✕ 不會關、一直 nag 到開 App 完成起床任務」。它跟 snooze 完全是兩回事。
- **「貪睡模式 / strict mode」已於 2026-06-10 移除**（kill-switch）：`Alarm.effectiveRequireAppToStop` 直接 `return false`，編輯頁 toggle 已拿掉。下游 strict 專屬 code（`StopAlarmIntent` strict 分支、`AlarmScheduler.scheduleNagsIfNeeded`、`AudioRecorder` strict gate、stored `requireAppToStop` 屬性）**保留但永不觸發**（user 要求先不清，怕連鎖問題）。
  - ⚠️ 接手做 snooze 時請注意：**不要把 snooze 又取名「貪睡模式」跟舊 strict 混淆**；strict 那套已是 dead code。

---

## 3. App 架構（跟 snooze 相關的部分）

### 3.1 兩條響鈴路徑（很重要）

| | 前景（App 在螢幕上） | 背景 / 鎖屏 / App 被關 |
|---|---|---|
| 誰響 | 自家 `AlarmRingView`（兒童起床畫面，語音/按鈕關閉） | **AlarmKit 系統警示**（Lock Screen / Dynamic Island） |
| 入口 | `HomeView.checkForegroundAlarm()`（每秒 tick）偵測到鬧鐘到點 → `enterForegroundAlarmMode()` 先把 AlarmKit cancel 掉 → `firingAlarm = alarm` → `.fullScreenCover` 顯示 `AlarmRingView` | `AlarmKitService.syncAlarm()` 排的 `AlarmManager.schedule(... .alarm ...)`；警示外觀由 `AlarmPresentation` 決定 |
| 檔案 | `Views/Alarm/AlarmRingView.swift`、`Views/Home/HomeView.swift` | `Services/AlarmKitService.swift` |

> **關鍵結論：snooze（貪睡按鈕 + slide to stop）只會出現在「背景/鎖屏的 AlarmKit 系統警示」上。**
> 前景的 `AlarmRingView` 是另一套自家 UI，預設不會有 snooze 按鈕（除非另外做）。

### 3.2 AlarmKit 接線（`Services/AlarmKitService.swift`）

- 需要 Apple 核發的 AlarmKit entitlement；`AlarmKitService.isAuthorized` 是 runtime 驗證（不可只信 cached `authorizationState`）。
- 警示外觀：`makePresentation(title:)` → 目前只給 `AlarmPresentation.Alert(title:stopButton:)`，stopButton 文字「我起床了」。
- `makeAttributes(alarmID:title:)` → `AlarmAttributes<SunnyWalkerAlarmMetadata>(presentation:metadata:tintColor:)`。
- 主要排程在 **`syncAlarm(_:)`**（這是真正在用的路徑，不是 `scheduleAlarm`/`scheduleRecurringAlarm` 那些舊的）。
  - ⚠️ **這個函式是雷區**：滿滿的 race-fix 註解（「AlarmKit 不會 re-arm 已 fire/stop 的 id」「cancel 不會停正在響的，要先 stop」「simulator 用 `.named()` 會 crash ToneLibrary」等）。
  - 目前的 schedule 呼叫是 4 路矩陣：`#if targetEnvironment(simulator)` × `strict ? StopAlarmIntent : DismissAlarmIntent`（strict 現在恆 false → 永遠走 `DismissAlarmIntent` 分支）。
  - 排程同時會 `AlarmAutoStopService.shared.arm(alarmID:fireDate:ringSeconds:)`，`ringSeconds = AppSettings.shared.alarmRingDurationMinutes * 60`。

### 3.3 Intents 在「分開的 target」（AppIntents extension）

`Intents/StopAlarmIntent.swift` 內含 `StopAlarmIntent`（strict）與 `DismissAlarmIntent`（non-strict），都是 `LiveActivityIntent`：

- ⚠️ **吃不到主 App 的型別**：檔頭註解明寫「compiled in a separate target」「cannot call AlarmAutoStopService here」。所以 intent 內**不能**呼叫 `AlarmKitService` / `AlarmAutoStopService` / `AppSettings` / SwiftData。
- 與主 App 溝通只能靠：`UserDefaults.standard`（例：`pendingAlarmKitAlarmID`、`dismissedAlarmID`）+ `NotificationCenter.post(.alarmFired)`。
- `StopAlarmIntent.supportedModes = .foreground(.immediate)`（開 App）；`DismissAlarmIntent.supportedModes = .background`（不開 App，只關鬧鐘）。
- intent 可以呼叫 `AlarmManager.shared.stop(id:)` / `.cancel(id:)`（它 import AlarmKit）。

### 3.4 自動停鈴（`Services/AlarmAutoStopService.swift`）

- 在主 App 端 `arm()`，靠 BGProcessingTask + DispatchTimer keep-alive，在響鈴時長到時 `stop()` 那顆 AlarmKit 鬧鐘。
- ⚠️ 只在「主 App 能在背景跑」時有效；App 被殺/純鎖屏時，是靠系統自己的響鈴時長。

---

## 4. 試過什麼（action / try，已還原）

1. **Alarm model** 加 `snoozeEnabled: Bool?` / `snoozeMinutes: Int?` / `maxRingCount: Int?`（Optional + `effective*` accessor，預設 true/5/3，夾 1–10，配合 SwiftData lightweight migration）。
2. **AlarmEditorView** 加 `snoozeCard`：貪睡 Toggle + 「貪睡間隔」Stepper(1–10) + 「最多響幾次」Stepper(1–10)，`saveAlarm()` 寫回。
3. **`SnoozeAlarmIntent.swift`**（AppIntents extension target，`.background`）：用 `UserDefaults.standard` 計數 `snoozeCount-<id>`，讀 `snoozeMax-<id>`，達上限就 `AlarmManager.shared.stop(id:)`。
4. **沒做、也沒套**：`AlarmKitService.makePresentation` 加 secondary 貪睡鈕、`syncAlarm` 加 `countdownDuration` + `secondaryIntent`、把 `SnoozeAlarmIntent` 加進 XcodeGen target、`Stop/DismissAlarmIntent` 真停時清 `snoozeCount`。

→ 以上 1–3 **全部還原刪除**，回到「沒有 snooze」的乾淨狀態。

---

## 5. 為什麼喊停（why stop）

1. **無法編譯驗證。** 撰寫環境是 Linux 沙箱，沒有 Xcode / Swift toolchain，AlarmKit 是 iOS 26（超出訓練知識截止）的新框架。
2. **關鍵那段在雷區、且 API 不確定。** 要把「recurring/fixed schedule + `countdownDuration(postAlert=N)` + `secondaryIntent` + `stopIntent` + `sound`」組進**同一個 `AlarmManager.AlarmConfiguration`**——這段必須改 `syncAlarm`（§3.2 的雷區）。如果 initializer 參數名/形狀猜錯，**不是只壞 snooze，是整個排程編不過、全 App 無法 build**。盲改這條路風險過高。
3. **跨 target 限制。** cap 計數與「每次再響的 per-ring auto-stop」需要在 AppIntents extension 內運作，但它摸不到 `AlarmAutoStopService`，只能用 `UserDefaults` 橋接（§3.3）。
4. **結構性限制（見 §7），就算寫完也只能做到部分。**

> user 在了解上述後，選擇「先不做 snooze，移除半成品」。本文件即為日後重做的依據。

---

## 6. 已確認的 AlarmKit API（研究來源見文末）

```swift
// 1) 警示按鈕
let stopButton   = AlarmButton(text: "我起床了", textColor: .white, systemImageName: "sun.max.fill")
let snoozeButton = AlarmButton(text: "貪睡",     textColor: .white, systemImageName: "zzz")

// 2) 警示（secondaryButton 可選；behavior 決定按下去的系統行為）
let alert = AlarmPresentation.Alert(
    title: "該起床囉",
    stopButton: stopButton,
    secondaryButton: snoozeButton,
    secondaryButtonBehavior: .countdown   // 或 .snooze
)
// .snooze    = 系統預設間隔（不可自訂 → 不符合「N 可設」）
// .countdown = 用 countdownDuration.postAlert 當再響間隔（→ 可自訂 N，這是我們要的）

// 3) 倒數/貪睡間隔
//    Alarm.CountdownDuration(preAlert:postAlert:)；postAlert = 貪睡再響間隔（秒）
//    讀回：alarm.countdownDuration?.preAlert / .postAlert
let countdown = Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(snoozeMinutes * 60))

// 4) 屬性（Metadata 必填型別，SunnyWalker 已有 SunnyWalkerAlarmMetadata: AlarmMetadata）
let attrs = AlarmAttributes<SunnyWalkerAlarmMetadata>(
    presentation: AlarmPresentation(alert: alert),
    metadata: SunnyWalkerAlarmMetadata(alarmID: idStr),
    tintColor: .orange
)

// 5) secondaryIntent：貪睡按鈕的自訂 callback（LiveActivityIntent，背景）
//    現有 StopAlarmIntent / DismissAlarmIntent 可當模板。

// 6) 狀態觀察：AlarmManager.shared.alarmUpdates (async sequence)；alarm.state = .countdown/.alerting/.paused
```

確定存在：`AlarmButton`、`AlarmPresentation.Alert(title:stopButton:secondaryButton:secondaryButtonBehavior:)`、`.snooze`、`.countdown`、`Alarm.CountdownDuration(preAlert:postAlert:)`、`secondaryIntent`、`AlarmManager.shared.alarmUpdates`、`alarm.countdownDuration`、`alarm.state`。

---

## 7. 結構性限制（即使做完也「做不到」的部分）

1. **實體鍵不能變貪睡。** AlarmKit 系統警示上，音量/側鍵被 iOS 直接接成「停止」，第三方攔不到、也不能改成 snooze。（user 已實測：strict 模式下按音量鍵鬧鐘就關了。）
2. **前景自家 `AlarmRingView` 沒有 snooze 按鈕。** snooze 只在背景/鎖屏的 AlarmKit 警示。若也要前景貪睡，得在 `AlarmRingView` 另外做一顆貪睡按鈕 + 自己的再響邏輯（另一筆工）。
3. **鎖屏 / App 被殺時，「再響的那幾次」的 per-ring auto-stop 無法用 App 端 `AlarmAutoStopService` 重新 arm**（intent 跨 target）。那幾次只能吃系統響鈴時長。**cap（最多響幾次）可由 intent 確保會停**，battery 疑慮主要靠 cap 守住。
4. **cap 的時機有 race：** 在「第 maxRingCount 次貪睡」那一刻於 intent 內 `stop()`，能不能即時取消系統已排的再響，需實機驗。

> 註：user 原本要 cap 的初衷（iPad 耗電）其實**已被現有「響鈴時長 1–10 分 auto-stop」覆蓋**——沒人理的單次響鈴本來就會自己停。cap 主要是擋「一直手動貪睡」的情境。

---

## 8. 建議實作步驟（給有 Xcode 的接手者）

> 原則：**先在 Xcode 用 autocomplete 把 §6 的 `AlarmManager.AlarmConfiguration` 確切 initializer 對出來，再動 `syncAlarm`。** snooze-off 路徑要 byte-for-byte 不動，新邏輯只在 snooze-on 分支，降 blast radius。

1. **Model**（`Models/Alarm.swift`）：加 `snoozeEnabled: Bool?` / `snoozeMinutes: Int?` / `maxRingCount: Int?`，配 `effectiveSnoozeEnabled`(預設 true)、`effectiveSnoozeMinutes`(預設 5, clamp 1–10)、`effectiveMaxRingCount`(預設 3, clamp 1–10)；`init` 設預設值。（Optional 配合 SwiftData migration。）

2. **編輯頁 UI**（`Views/Settings/AlarmEditorView.swift`）：加 `snoozeCard`（Toggle + 兩個 Stepper），插在 `dismissMethodCard` 與 `ringtoneCard` 之間；`@State` + `init`（edit 模式從 `effective*` 帶入）+ `saveAlarm()` 寫回。

3. **警示外觀**（`AlarmKitService.makePresentation`）：改成 `makePresentation(title:snooze:)`，snooze 時帶 `secondaryButton` + `secondaryButtonBehavior: .countdown`；`makeAttributes` 多收一個 `snooze` 參數往下傳（給預設值 `false` 讓舊 caller 不爆）。

4. **排程**（`AlarmKitService.syncAlarm`）：
   - snooze-on 時：`UserDefaults.standard.set(alarm.effectiveMaxRingCount, forKey: "snoozeMax-\(idStr)")`、`removeObject("snoozeCount-\(idStr)")`。
   - schedule config 帶 `countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(alarm.effectiveSnoozeMinutes*60))` + `secondaryIntent: SnoozeAlarmIntent(alarmID: idStr)`。
   - ⚠️ 用 Xcode autocomplete 確認 `AlarmManager.AlarmConfiguration` 的確切 initializer；保留 simulator/strict 的 `#if` 矩陣（strict 現恆 false，可簡化為單分支）。
   - snooze-off 維持現有程式不動。

5. **`SnoozeAlarmIntent`**（新檔，放 `Intents/`，加進 **AppIntents extension target**，見 `project.yml`）：`LiveActivityIntent` + `.background`；`@Parameter alarmID`；`perform()`：讀 `snoozeMax-<id>`、`snoozeCount-<id>+1` 寫回，`if count >= max { AlarmManager.shared.stop(id:); 清 count }`。用 `StopAlarmIntent` 當模板。

6. **真停時清計數**：`StopAlarmIntent` / `DismissAlarmIntent` 的 `perform()` 內 `UserDefaults.standard.removeObject(forKey: "snoozeCount-\(alarmID)")`，避免跨天殘留。

7. **Live Activity / Widget extension**：AlarmKit 倒數通常需要 Live Activity（`ActivityConfiguration(for: AlarmAttributes<...>.self)`）。**先確認專案是否已有**（搜 `ActivityConfiguration` / Widget target）；若沒有、且 `.countdown` 需要它，要補一個 Widget extension。

8. **每筆 per-ring auto-stop**：第一次響由現有 `AlarmAutoStopService.arm()` 顧；貪睡再響那幾次的 app 端 auto-stop 屬已知限制（§7.3），先接受靠系統響鈴時長，cap 守 battery。

---

## 9. 必須在實機 / Xcode 驗證的 Open Questions

1. `AlarmManager.AlarmConfiguration` 把 **schedule + countdownDuration + stopIntent + secondaryIntent + sound** 組在一起的**確切 initializer 形狀與參數名**？（`.alarm(...)` 便利建構子吃不吃 `countdownDuration`/`secondaryIntent`？還是要用 full init？）
2. `.countdown` 行為在 **App 被殺 / 純鎖屏**時，會不會由系統自動「過 postAlert 再響」？（預期會，但要驗。）
3. 在 `SnoozeAlarmIntent.perform()` 內 `stop()` 能否**可靠取消**系統已排的再響（cap 的 race）？
4. 設了 secondaryButton 後，**實體鍵**在 AlarmKit 警示上會變停止還是貪睡？（user 在「無 snooze 按鈕」時實測是停止。）
5. 專案是否**已有 Live Activity / Widget extension**？`.countdown` 是否強制需要它才能顯示倒數？
6. `secondaryButtonBehavior` 與 `secondaryIntent` 兩者**同時設**時，系統行為（先跑 intent 還是先 snooze、能不能在 intent 內否決 snooze）？

---

## 10. 相關檔案 / 函式索引

| 檔案 | 重點 |
|---|---|
| `Models/Alarm.swift` | `@Model Alarm`；要加 snooze 欄位 + `effective*`；`effectiveRequireAppToStop` 已恆 false（strict 已移除） |
| `Views/Settings/AlarmEditorView.swift` | 鬧鐘編輯頁；`dismissMethodCard`（口令關閉）；`saveAlarm()`；要加 `snoozeCard` |
| `Services/AlarmKitService.swift` | `makePresentation` / `makeAttributes` / **`syncAlarm`（雷區）** / `stop` / `removeAlarm`；snooze 接線主戰場 |
| `Intents/StopAlarmIntent.swift` | `StopAlarmIntent`(.foreground) / `DismissAlarmIntent`(.background)；**分開 target**；UserDefaults+.alarmFired 溝通；`SnoozeAlarmIntent` 的模板 |
| `Services/AlarmAutoStopService.swift` | 響鈴時長 auto-stop（`arm/disarm/checkAndStopOverdue`）；intent 端摸不到 |
| `Services/AlarmScheduler.swift` | UNNotification fallback + `scheduleNagsIfNeeded`/`cancelNags`（strict 專屬，現 dead） |
| `Views/Home/HomeView.swift` | `checkForegroundAlarm`（前景 in-app ring）、`enterForegroundAlarmMode`/`enterBackgroundAlarmMode`、`presentRing` |
| `Views/Alarm/AlarmRingView.swift` | 前景兒童起床畫面（語音 time-multiplex）；若要前景貪睡在這加 |
| `project.yml` (XcodeGen) | target 成員；新 intent 要加進 AppIntents extension target |
| `Localizable.xcstrings` | 「貪睡模式」字串現為孤兒（strict 已移除） |

---

## 11. 研究來源（AlarmKit API）

- BleepingSwift — Scheduling Alarms with AlarmKit: https://bleepingswift.com/blog/scheduling-alarms-with-alarmkit （確認 `AlarmPresentation.Alert(... secondaryButton:secondaryButtonBehavior:)` 與 `.snooze`）
- Nil Coalescing — Schedule a countdown timer with AlarmKit: https://nilcoalescing.com/blog/CountdownTimerWithAlarmKit/ （確認 `Alarm.CountdownDuration` 的 `preAlert/postAlert`、`alarmUpdates`、`alarm.state`、Live Activity 需求）
- Apple — AlarmKit: https://developer.apple.com/documentation/AlarmKit
- Apple WWDC25 session 230 — Wake up to the AlarmKit API: https://developer.apple.com/videos/play/wwdc2025/230/

> ⚠️ 以上多為第三方教學；**最終以 Xcode autocomplete + Apple 官方文件為準**，尤其是 §9 Q1 的 `AlarmConfiguration` initializer。
