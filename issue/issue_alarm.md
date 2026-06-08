# Issue: 鬧鐘在背景無法自動停止

**日期**: 2026-06-07（第二輪 session 已更新，見文末「2026-06-07 第二輪修正」）  
**狀態**: 核心失效點已修（interruption 復活），待真機驗證  
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

### 4. `AlarmAutoStopService.swift` 未加入 Xcode project ✅ 已解（2026-06-08）
- 症狀：Xcode 4 個 `Cannot find 'AlarmAutoStopService' in scope`（AlarmKitService 內 4 處引用）。
- root cause：本專案 pbxproj **逐檔列舉**（非 synchronized folder group），Write tool 建立的
  新檔沒被加進 pbxproj，所以 compile 找不到。
- 解法：`cd ~/Documents/SunnyWalker && xcodegen generate`（project.yml `- path: SunnyWalker`
  會收進新檔）→ Xcode Clean Build Folder（⇧⌘K）→ 重 build。
- ⚠️ **連帶雷**：xcodegen 會用 project.yml 的 `info.properties` 重建 Info.plist，
  原本手改的 `UIBackgroundModes: processing` + `BGTaskSchedulerPermittedIdentifiers`
  會被洗掉 → `BGTaskScheduler.register` crash。**已先把這兩項補進 project.yml**
  （info.properties），所以 regenerate 後 Info.plist 仍正確。

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

---

# 2026-06-07 第二輪修正

## 調查結論（修正原本的建議方向）

### ❌ 方向 B（本地通知喚醒）不可行
本地 UNNotification **無法在背景執行程式碼**：
- `willPresent` 只在 app 前景時觸發
- background delivery（`content-available`）只適用 **remote push**，本地通知沒有
- Notification Service Extension 也只攔 remote push

原文件描述的「通知喚醒 app → 呼叫 stop()」這條路在 iOS 上不存在。

### ❌ 方向 C（AlarmKit 原生 timeout）無公開 API
查過 AlarmKit（iOS 26.x）文件與 dev forums：`AlarmConfiguration` 只有
schedule / attributes / stopIntent / secondaryIntent / sound / countdownDuration（pre/postAlert
是倒數與貪睡用，不是響鈴時長）。**沒有 ring-duration / timeout 參數**。
系統 Clock app 行為是響 ~15 分鐘自動靜音；AlarmKit 鬧鐘是否套用同一個
SpringBoard 上限**未文件化、未驗證**（真機測試項目之一）。

### ★ 真正的失效點：audio interruption
重新對 log 推理：第二份 log「guard log 跑到響鈴時刻、之後全停」代表
**app 在背景其實活著（keep-alive 有效），是在「鬧鐘響起的那一刻」死掉的**。
原因：AlarmKit 鬧鐘由 SpringBoard 播音，會 INTERRUPT app 的 audio session
（即使 `.mixWithOthers`）→ 靜音 player 停 → app 失去 audio keep-alive →
立刻被 suspend → `stopAt` 的 DispatchTimer 永遠執行不到。
**也就是說 Layer 2 在最需要活著的時刻必定死亡** — 這是原架構的根本漏洞。

## 本輪修改

| 檔案 | 修改內容 |
|------|---------|
| `Services/AlarmAutoStopService.swift` | 重寫，加 Layer 2.5 + watchdog（見下） |
| `Views/Home/HomeView.swift` | `enterBackgroundAlarmMode()` 加 transition protection（UIApplication bg task）；scenePhase → .active 加 `endBackgroundLifecycle()`（gate：`firingAlarm == nil`，避開 AlarmRingView audio session 560557684 雷） |

`AlarmAutoStopService` 新增：

1. **Layer 2.5 — interruption 復活（核心修復）**
   監聽 `AVAudioSession.interruptionNotification`：
   - `.began`（= 鬧鐘剛開始響，app 此刻還活著）→ 立刻拿 `UIApplication.beginBackgroundTask`
     （~30s 額度）+ 夾 stopAt + 每秒重試 `setActive(true)+play()`（最多 25 次）。
     mixable session 在系統鬧鐘播音期間通常允許重新啟動 → keep-alive 恢復 → timer 照常跑。
   - `.ended` → 直接復活 player。
2. **Watchdog（背景 keep-alive 期間每 5 秒）**
   (a) `stopAt` 過期備援 stop；(b) player 死了重踢；(c) 偵測 `alarmState == alerting`
   → `stopAt = min(原值, 偵測時刻 + ringSeconds)`，修正預測 fireDate 錯誤。
3. **Transition protection** — 背景轉場用 bg task 保護 `syncAllEnabled` + 音訊啟動，
   避免轉場途中被 suspend。
4. **startSilentAudio 重試 3 次**（0.5s 間隔）— HomeView 背景分支剛 `setActive(false)`
   （解 UN ducking 雷），馬上啟動會撞 session 競態（同 AudioPlayer 560557684 修法）。
5. **BGTask 機會性升級** — `handleBGTask` 停完 overdue 後呼叫 `beginBackgroundLifecycle()`：
   若 iOS 恰好在響鈴期間給執行權，趁機把 Layer 2 拉起來（整夜 suspended 情境的唯一逃生門）。
6. `ArmedEntry` 加 `ringSeconds` / `alertingSeenAt`（optional，舊持久化資料 decode 相容）。
7. DispatchTimer 加 `leeway: .milliseconds(100)`；`installDispatchTimer(replace:)` 支援夾 stopAt 後重排。

## 殘餘風險（iOS 平台限制，無程式解）

- interruption 期間 `setActive(true)` 若被 iOS 拒絕 25 次 → app 照樣 suspend，
  回到 Layer 1。log 會留 `recoverPlayback: GAVE UP`。
- ~~整夜 suspended（鬧鐘 > 10 分鐘後才響）~~ → **已於第三輪封掉**（見下）。

---

# 2026-06-07 第三輪：鎖住「最長響 10 分鐘」硬性保證

決策（Rex）：**「鬧鐘最長響 10 分鐘」是 app 的硬性保證**（iPhone 內建鬧鐘也會自動停），
不接受「>10 分鐘才響就只靠 BGTask」的缺口。

## 修改

1. **拿掉 `beginBackgroundLifecycle` 的 10 分鐘門檻** — 只要有 armed alarm，
   進背景就無條件啟動靜音 keep-alive + DispatchTimer + watchdog（整夜也保活）。
2. **watchdog 改自適應間隔省電** — 最近的 fire/stopAt 在 10 分鐘內 → 5s 密集輪詢；
   否則 60s 稀疏輪詢。跨進/跨出視窗時自動重排程（log：`watchdog: interval → Ns`）。
3. `lookAheadMinutes` 語意改為「接近響鈴視窗」（= ring duration 上限 10 分，
   與 AppSettings 的 1...10 一致）。

## 取捨（已接受）

- 整夜 0 音量音訊保活的電量成本：可靠性 > 電量，小孩鬧鐘情境手機通常整夜充電。
- iOS 若因記憶體壓力整夜殺掉 app → keep-alive 消失，回到 Layer 1 BGTask +
  系統自身自動靜音（Clock ~15 分；AlarmKit 未文件化）。此為平台限制，無程式解。

## 追加真機驗證項目

6. **整夜情境**：睡前設隔天早上的鬧鐘 → 鎖屏整夜 → 早上不碰手機，
   確認鬧鐘在 ring duration 到點自動停。觀察整夜 log 是否有
   `watchdog: interval → 5s`（進入 10 分鐘視窗）→ `interruption BEGAN` → `RECOVERED`
   → `DispatchTimer fired`。同時記錄整夜電量消耗（基準對照：關鬧鐘的一夜）。

---

# 2026-06-08 第四輪（最終定案）：響鈴視窗模型 + timeout 統計

第三輪的「整夜無條件保活」被 Rex 否決。最終產品定位：

> **給小朋友的提醒型鬧鐘**。響鈴只有 1~10 分鐘；超過 10 分鐘 app 也要自動停止
> 背景運作（不整夜保活耗電）。無人回應時 app 要能**獨立完成**「自動停鈴 + 記錄」，
> 之後做準時率 / 回應率統計。

## 生命週期（最終版）

```
進背景：
  最近 fire 時刻 ≤ 10 分鐘 → 啟動 keep-alive（靜音音訊 + stopAt timer + 5s watchdog）
  最近 fire 時刻 > 10 分鐘 → 不保活，只排 BGTask → app 自然 suspend（省電）

響鈴視窗（fire → fire + ring 1~10 分）：
  interruption 復活撐住 keep-alive → stopAt 到點 → queue timeout 記錄 → stop()
  → disarm → dispatchTimers 清空 → 自動 teardown（audio/watchdog 全停）→ app suspend
  ＝「超過十分鐘也自動停止 app 運作」

下次回前景：
  checkAndStopOverdue 補停漏網鬧鐘（也補 queue timeout 記錄）
  → drainTimeoutRecords() 把 pending 轉成 WakeRecord(dismissMethod:"timeout") 入 SwiftData
```

## 修改

| 檔案 | 內容 |
|------|------|
| `AlarmAutoStopService.swift` | 恢復 10 分鐘視窗門檻（以 **fire 時刻**判定，非 stopAt）；移除自適應 watchdog（回固定 5s，只在視窗內跑）；新增 `PendingTimeoutRecord` queue（UserDefaults，背景不碰 SwiftData）＋四個 auto-stop 點（DispatchTimer / watchdog / BGTask / checkAndStopOverdue）都會 queue，dedupe 同次響鈴 |
| `HomeView.swift` | `.active` 延遲 0.5s 呼叫 `drainTimeoutRecords()` → 插入 `WakeRecord(dismissMethod:"timeout")` |
| `WakeHistoryView.swift` | dismissMethod 加 `timeout` case（icon `bell.slash.fill`、label `method_timeout`） |
| `Localizable.xcstrings` | 加 `method_timeout`（zh-Hant「沒有回應（自動停止）」/ en "No response (auto-stopped)"） |

## 統計語意

- `WakeRecord.dismissMethod == "timeout"`：響鈴視窗內無人回應，`wokeAt` = 自動停鈴時刻
  （不是起床時刻），`responseSeconds` ≈ ring duration。
- 回應率 = (voice+button+fallback) / 全部；準時率可用 responseSeconds 門檻計。
- TODO（之後做統計頁時）：前景 AlarmRingView 的 ringTimeout 自動關閉目前**沒有**記
  WakeRecord — 要補一筆 "timeout" 才不會漏前景無人回應的場景。

## 接受的取捨

- 整夜 suspended 期間第一段響鈴（>10 分鐘才響、BGTask 沒觸發）：app 停不了鈴，
  靠系統自身自動靜音（Clock ~15 分，AlarmKit 未文件化 — 驗證項目 4）。
  統計不會漏：下次開 app 補停 + 補 timeout 記錄。
- 換來：不整夜保活、電量成本只發生在響鈴視窗（≤ ~20 分鐘）。

## 驗證項目修訂

- 項目 6 改為：整夜情境驗證「鬧鐘響後 app 不被喚醒時，系統多久自動靜音」＋
  早上開 app 後 WakeHistory 出現「沒有回應（自動停止）」記錄。
- 新增項目 7：視窗內無人回應 → 自動停鈴後，用 Xcode Debug Navigator 確認
  app 已無 CPU 活動（teardown 成功、不殘留 watchdog）。

## 真機驗證清單

1. **≤10 分鐘鬧鐘（Layer 2 主路徑）**：設 2 分鐘後鬧鐘、ring duration 1 分 → 鎖屏。
   預期 log：`startSilentAudio` → `watchdog started` → 響鈴時 `interruption BEGAN` →
   `recoverPlayback: RECOVERED on attempt N` → `DispatchTimer fired` → `stop AFTER=…` 鈴聲停。
   ★ 若看到 `GAVE UP` = interruption 復活被 iOS 擋，回報 attempt 數。
2. **alerting 夾值**：觀察 `alerting NOW — stopAt clamped` 是否出現（預測 fireDate 偏差時）。
3. **BGTask**：lldb 手動觸發驗證流程
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.sunnywalker.alarm.autostop"]`
4. **系統 15 分鐘上限**：>10 分鐘後的鬧鐘、不開 app，計時鬧鐘自己停的時間。
   這決定整夜情境要不要再加碼。
5. **回前景不打架**：鬧鐘在 in-app 響時鎖屏再解鎖，確認 AlarmRingView 鈴聲不被
   `endBackgroundLifecycle` 砍掉（已 gate `firingAlarm == nil`）。
