# Issue: 鬧鐘在背景無法自動停止

**日期**: 2026-06-07  
**狀態**: 部分解決（已加架構，未驗證）  
**相關檔案**: `AlarmAutoStopService.swift`, `AlarmKitService.swift`, `HomeView.swift`, `SunnyWalkerApp.swift`

---

## 問題描述

AlarmKit 鬧鐘設定 1–2 分鐘後，**在背景不會自動停止**。  
只有使用者手動打開 app 或按鎖屏停止按鈕，鬧鐘才會停。

---

## 根本原因分析

### 已確認的兩個場景

**場景 A：使用者開 App，但鬧鐘還是停不下來**

根本原因：`enterForegroundAlarmMode()` 只呼叫 `cancel()`，沒有呼叫 `stop()`。  
`cancel()` 只把鬧鐘從排程移除，**無法停止正在響的鬧鐘**，需要先呼叫 `stop()` 才能靜音。

✅ **已修復**：`enterForegroundAlarmMode()` 和 `syncAlarm()` 都改為先 `stop()` 再 `cancel()`。

---

**場景 B：使用者從未打開 App，鬧鐘在背景一直響**

這是核心問題。AlarmKit 的系統鬧鐘由 SpringBoard 播放，不是 app 的 AVAudioSession，  
app 完全 suspended 時沒有任何 callback 可以攔截。

---

## Log 記錄（實際測試的兩份）

### 第一份 Log（設定 2 分鐘）
```
🏠 checkForegroundAlarm GUARD: scenePhase=background firingAlarm=nil akAuthorized=true [x2]
```
→ App 有在背景短暫活著（AlarmKit 喚醒），但沒有進 foreground，AlarmRingView 從未顯示。

### 第二份 Log（設定 1 分鐘）
```
🏠 checkForegroundAlarm GUARD: scenePhase=background firingAlarm=nil akAuthorized=true
（然後就沒了，完全停止 log）
```
→ App 被系統 suspend，沒有任何自動停止機制可以執行。

---

## 已嘗試的手法

### 1. Log 增加（偵錯用，非修復）
- `AlarmRingView.onAppear/onDisappear` 加時間戳記 log
- `AlarmKitService.stop()` 加 BEFORE/AFTER state log
- `HomeView.checkForegroundAlarm` 加每分鐘一次的 guard log
- `enterForegroundAlarmMode()` 加 stop+cancel 前後 log

### 2. cancel() → stop() + cancel() 修復（✅ 有效）
- `enterForegroundAlarmMode()` 改為 stop + cancel
- `syncAlarm()` 改為 stop + cancel before reschedule

### 3. AlarmAutoStopService 架構（⚠️ 已寫入，未驗證）

這次 session 實作了 `AlarmAutoStopService.swift`，採 State Machine Push-down 架構：

**Layer 1 — BGProcessingTask**：
- `syncAlarm()` 呼叫 `arm(alarmID, fireDate, ringSeconds)`
- `arm()` 寫 `stopAt = fireDate + ringSeconds` 到 UserDefaults
- 提交 `BGProcessingTaskRequest(earliestBeginDate: stopAt)`
- BGTask 被 iOS 喚醒時，呼叫 `AlarmKitService.stop(id:)`

**Layer 2 — 靜音音訊 + DispatchSourceTimer**：
- `enterBackgroundAlarmMode()` 完成 sync 後呼叫 `beginBackgroundLifecycle()`
- 如果最近的 `stopAt - now ≤ 10 分鐘`，啟動 `AVAudioPlayer(sunny_wake.caf, vol=0, loop)`
- 靠 `audio` background mode 讓 app 保持活著
- `DispatchSourceTimer` 在 `stopAt` 精準觸發 `stop()`

**Fallback — scenePhase → .active**：
- 每次 app 進前景呼叫 `checkAndStopOverdue()`
- 如果 `stopAt <= now` → 強制 stop

---

## 目前已修改的檔案清單

| 檔案 | 修改內容 |
|------|---------|
| `Services/AlarmAutoStopService.swift` | **新增** — 完整 auto-stop 服務 |
| `Info.plist` | 加 `BGTaskSchedulerPermittedIdentifiers: [com.sunnywalker.alarm.autostop]`，UIBackgroundModes 加 `processing` |
| `SunnyWalkerApp.swift` | 加 `BGTaskScheduler.shared.register(...)` 在 `didFinishLaunching` |
| `Services/AlarmKitService.swift` | `syncAlarm()` 呼叫 `arm()`；`stop(id:)` 呼叫 `disarm()` |
| `Views/Home/HomeView.swift` | `enterBackgroundAlarmMode()` 加 `beginBackgroundLifecycle()`；`scenePhase → .active` 加 `checkAndStopOverdue()` |
| `Intents/StopAlarmIntent.swift` | 移除對 `AlarmAutoStopService` 的直接呼叫（跨 target 問題） |

---

## 已知問題 / 尚未驗證

### 1. BGProcessingTask 可靠性不確定
- BGProcessingTask 是 iOS **best-effort**，不保證在精確時間觸發
- 在鎖屏、未充電、飛航模式下可能延遲很久甚至不觸發
- Apple 限制：BGProcessingTask 通常只在充電 + WiFi 時可靠

### 2. 靜音音訊 Layer 2 未在真機驗證
- `AVAudioPlayer(vol=0, loop)` 啟動後，iOS 是否真的不把它 suspend 掉，未知
- 若 iOS 發現 audio session 無聲音輸出，可能仍會 suspend app
- Apple 審核可能拒絕：background audio 必須提供使用者可感知的價值

### 3. 跨 Target 問題（已繞過但未解決）
- `StopAlarmIntent` / `DismissAlarmIntent` 在獨立 target（可能是 App Intents Extension）
- 無法直接呼叫主 app target 的 `AlarmAutoStopService`
- 目前的 workaround：intent 不呼叫 disarm，靠 app 進前景時的 `enterForegroundAlarmMode` → `stop()` → `disarm()` 清理

### 4. `AlarmAutoStopService.swift` 未加入 Xcode project（如果不用 XcodeGen）
- 用 Write tool 建立的檔案，如果是手動管理 xcodeproj 需要在 Xcode 裡 Add to Target

---

## 接下來的建議方向

### 方向 A：驗證現有架構（優先）
1. 在真機上測試 BGProcessingTask 是否能在 `stopAt` 附近觸發
2. 用 Xcode lldb 指令手動觸發 BGTask 驗證流程：
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.sunnywalker.alarm.autostop"]
   ```
3. 觀察 log：是否看到 `🛡️ AlarmAutoStop.handleBGTask fired` 和 `🛡️ BGTask: stopping overdue`

### 方向 B：改用本地通知喚醒 app（更可靠）
在 `syncAlarm()` 時，同時排一個本地 UNNotification，觸發時間 = `stopAt`：
- 通知不顯示 banner（設定 `UNNotificationContent.sound = nil`，不顯示）
- `userNotificationCenter(_:willPresent:)` 或 background delivery 喚醒 app
- 喚醒後呼叫 `AlarmKitService.stop()`

這比 BGProcessingTask 更可靠，因為 UNNotification 的 delivery 比 BGTask 準時。

### 方向 C：只靠 AlarmKit 本身的 timeout（簡單但有限）
AlarmKit 的 `.alarm` 本身可能有 system-level 的 timeout（類似系統時鐘 app 的行為）。  
調查 AlarmKit API 是否有 `timeout` 或 `ringDuration` 參數可以直接設定，讓系統自動停止。

---

## App 關鍵架構背景

```
app 在前景 (scenePhase == .active)
  → AlarmKit 被 stop()+cancel()
  → foregroundAlarmTick (1s Timer) 偵測到鬧鐘時間 → 顯示 AlarmRingView（in-app 鈴聲）
  → AlarmRingView 的 ringTimeoutTask 負責前景的 auto-stop

app 在背景
  → AlarmKit 擁有鬧鐘（lock screen UI + 系統鈴聲）
  → app 本身 suspended，無法執行任何 code
  → 唯一機會：BGProcessingTask / UNNotification background delivery
```

**重要 API 區分**：
- `AlarmManager.cancel(id:)` → 移除排程，**不停止正在響的鬧鐘**
- `AlarmManager.stop(id:)` → **停止正在響的鬧鐘**（這才是關鍵）

---

## 參考檔案路徑

```
SunnyWalker/
├── SunnyWalkerApp.swift          # AppDelegate + BGTask registration
├── Services/
│   ├── AlarmAutoStopService.swift  # 新架構（本 issue 的核心）
│   └── AlarmKitService.swift       # stop()/cancel()/syncAlarm()
├── Views/Home/HomeView.swift       # scenePhase 管理、enterBackground/ForegroundAlarmMode
├── Views/Alarm/AlarmRingView.swift # in-app 鈴聲 + ringTimeout（前景用）
└── Intents/StopAlarmIntent.swift   # StopAlarmIntent / DismissAlarmIntent（獨立 target）
```
