# 鬧鐘背景自動停止 — 技術文件

> 狀態：✅ 真機驗證成功（2026-06-08）
> 相關檔案：`Services/AlarmAutoStopService.swift`、`Services/AlarmKitService.swift`、
> `Views/Home/HomeView.swift`、`SunnyWalkerApp.swift`、`Models/WakeRecord.swift`
> 對應 debug 過程：`issue/issue_alarm.md`

---

## 1. 問題

AlarmKit 鬧鐘設定後，**在背景不會自動停止**——只有使用者手動開 app 或按鎖屏停止鈕才會停。

產品定位是「給小朋友的提醒型鬧鐘」：響鈴只有 1~10 分鐘，**超過時間沒人理也要自動停**，
而且 app 要能獨立完成「停鈴 + 記錄沒回應」，之後做準時率／回應率統計。

---

## 2. 兩個關鍵的 API 與平台事實

| 事實 | 說明 |
|------|------|
| `AlarmManager.cancel(id:)` | 只把鬧鐘移出排程，**不會停止正在響的鬧鐘** |
| `AlarmManager.stop(id:)` | **這才會讓正在響的鬧鐘靜音**（核心） |
| AlarmKit 鬧鐘由 SpringBoard 播放 | 不是 app 的 AVAudioSession；app suspended 時沒有任何 callback 可攔截 |
| AlarmKit 一響就把 app 踢到背景 | 即使 app 在前景，系統黑標一出現 app 就被 background |
| 無 ring-duration API | AlarmKit（iOS 26.x）的 `AlarmConfiguration` 沒有響鈴時長/timeout 參數 |
| 本地通知無法在背景跑程式 | `willPresent` 只在前景；background delivery 只給 remote push。**不能靠本地通知喚醒 app 停鈴** |

這兩條死路（原本以為可行的「方向 B 本地通知喚醒」「方向 C 原生 timeout」）都不存在，所以必須自己保活。

---

## 3. 核心失效點：audio interruption

最初的設計是「進背景時播 0 音量音訊（`audio` background mode）保活 → DispatchSourceTimer 在
`stopAt` 精準呼叫 `stop()`」。但實測發現 app **在鬧鐘響起的那一刻死掉**：

```
AlarmKit 鬧鐘響（SpringBoard 播音）
  → INTERRUPT app 的 AVAudioSession（即使設了 .mixWithOthers）
  → 0 音量保活 player 被停
  → app 失去 audio keep-alive
  → 立刻被 iOS suspend
  → stopAt 的 DispatchSourceTimer 永遠執行不到 ← 停不下來
```

log 特徵：背景的每分鐘 guard log 一路正常，**到響鈴時刻後完全停止**。
也就是 keep-alive 在「最需要它活著的瞬間」必定死亡——這是原架構的根本漏洞。

---

## 4. 最終架構：響鈴視窗模型

`AlarmAutoStopService`（`@MainActor` singleton）採「只在響鈴視窗運作、響完自動 teardown」的生命週期。

```
進背景（HomeView.enterBackgroundAlarmMode）：
  syncAllEnabled() 把 AlarmKit 重新排好（每個 syncAlarm 內呼叫 arm()）
  beginBackgroundLifecycle()：
    最近的 fire 時刻 ≤ 10 分鐘 → 啟動 keep-alive（靜音音訊 + stopAt timer + 5s watchdog）
    最近的 fire 時刻 > 10 分鐘 → 不保活，只留 BGTask → app 自然 suspend（省電）

響鈴視窗（fire → fire + ringDuration）：
  Layer 2.5 interruption 復活撐住 keep-alive
  → stopAt 到點 → queue timeout 記錄 → AlarmKitService.stop()
  → disarm() → dispatchTimers 清空 → 自動 teardown（音訊/watchdog 全停）→ app suspend
  ＝「超過十分鐘也自動停止 app 背景運作」

回前景（HomeView.scenePhase → .active）：
  endBackgroundLifecycle() 收掉 keep-alive
  checkAndStopOverdue() 補停漏網的鬧鐘（同時 queue timeout 記錄）
  drainTimeoutRecords() 把 pending 轉成 WakeRecord 入 SwiftData
```

### Layer 1 — BGProcessingTask（best-effort 保險）

- `arm()` 寫 `stopAt = fireDate + ringSeconds` 到 UserDefaults，提交
  `BGProcessingTaskRequest(earliestBeginDate: stopAt)`。
- handler（`SunnyWalkerApp.didFinishLaunching` 註冊）被喚醒時停掉所有 overdue 鬧鐘。
- BGTask 是 best-effort，鎖屏未充電時常常不觸發，**只當最後一道保險**。
- 機會性升級：handler 停完 overdue 後呼叫 `beginBackgroundLifecycle()`——若 iOS 剛好在
  響鈴期間給了執行權，趁機把 Layer 2 拉起來（整夜 suspended 情境的唯一逃生門）。

### Layer 2 — 靜音音訊 + DispatchSourceTimer

- 0 音量 `AVAudioPlayer`（loop）＋ `.playback` + `.mixWithOthers`，靠 `audio` background
  mode 保活，**不蓋過 AlarmKit 鈴聲**。
- 每個 armed alarm 一個 `DispatchSourceTimer`，在 `stopAt` 精準 `stop()`。
- `startSilentAudio` 失敗會重試 3 次（0.5s 間隔）——HomeView 進背景剛 `setActive(false)`
  解 UN 鈴聲 ducking，此時啟動會撞 session 競態（同 `AudioPlayer` 的 560557684 雷）。

### Layer 2.5 — audio interruption 復活（核心修復）

監聽 `AVAudioSession.interruptionNotification`：

- `.began`（≈ AlarmKit 鬧鐘剛開始響，app 此刻還活著）：
  1. `UIApplication.beginBackgroundTask`（~30s 額度）撐住不被 suspend
  2. `clampStopAtForAlertingAlarms` 夾 stopAt
  3. 每秒重試 `setActive(true) + play()`（最多 25 次）把 mixable 靜音 player 救回來
     ——mixable session 在系統鬧鐘播音期間通常允許重新啟動 → keep-alive 恢復 → timer 照常跑。
- `.ended`：直接復活 player。

### Watchdog（5 秒輪詢，只在響鈴視窗）

- (a) `stopAt` 過期 → `stop()`（one-shot timer 被凍結漏掉時的備援）
- (b) 靜音 player 死了 → 重新踢活
- (c) `alarmState == alerting` → `stopAt = min(原值, 偵測時刻 + ringSeconds)`
      （預測 fireDate 與 AlarmKit 實際觸發時刻不一致時的保險）

---

## 5. 「沒有回應」統計

無人在響鈴視窗內回應 → 自動停鈴。背景 service **不直接碰 SwiftData**，改走 queue：

```
auto-stop 四個觸發點（DispatchTimer / watchdog / BGTask / checkAndStopOverdue）
  → queueTimeoutRecord()：寫 PendingTimeoutRecord 到 UserDefaults（dedupe 同一次響鈴）
回前景 HomeView.drainTimeoutRecords()
  → WakeRecord(dismissMethod: "timeout", wokeAt: 自動停鈴時刻)
```

統計語意：

- `dismissMethod`：`voice` / `button` / `fallback` = 有回應；`timeout` = 沒回應。
- 回應率 = 有回應 / 全部；平均回應時間只算有回應的（timeout 的 `responseSeconds` ≈ 響鈴時長會拉高平均）。
- WakeHistory 頁可匯出 `.md`（含上述統計 + 逐筆表格）到「檔案」App，再分享到 LINE / 未來 lode_iphone。

> TODO：前景 `AlarmRingView` 的 ringTimeout 自動關閉目前**沒有**記 WakeRecord，
> 做統計頁時要補一筆 `timeout`，否則前景無人回應的場景會漏。

---

## 6. 接受的取捨（iOS 平台限制，無程式解）

- **整夜 suspended、鬧鐘 >10 分鐘後才響**：第一段響鈴只能靠 Layer 1 BGTask（best-effort）+
  系統自身自動靜音（Clock app 約 15 分鐘；AlarmKit 是否相同未文件化）。
  統計不會漏：下次開 app 由 `checkAndStopOverdue` 補停 + 補 timeout 記錄。
- interruption 期間 `setActive(true)` 若被 iOS 拒絕 25 次 → app 照樣 suspend，回到 Layer 1。
  log 會留 `recoverPlayback: GAVE UP`。
- 電量成本只發生在響鈴視窗（≤ ~20 分鐘），不整夜保活。

---

## 7. 建置陷阱（XcodeGen）

新增 `AlarmAutoStopService.swift` 後出現 4 個 `Cannot find 'AlarmAutoStopService' in scope`：

- root cause：本專案 `project.pbxproj` 是**逐檔列舉**（非 synchronized folder group），
  用 Write/手動建立的新檔不會自動進 build target。
- 解法：`xcodegen generate`（`project.yml` 的 `sources: - path: SunnyWalker` 整個資料夾會收進新檔）
  → Xcode ⇧⌘K Clean → 重 build。
- ⚠️ 連帶雷：`xcodegen generate` 會用 `project.yml` 的 `info.properties` 重建 `Info.plist`，
  手改的 `UIBackgroundModes: processing` + `BGTaskSchedulerPermittedIdentifiers` 會被洗掉
  → `BGTaskScheduler.register` crash。**已把這兩項補進 `project.yml`**，regenerate 後 Info.plist 仍正確。

---

## 8. 真機驗證清單

1. **≤10 分鐘鬧鐘（Layer 2 主路徑）**：設 2 分鐘後鬧鐘、ring duration 1 分 → 鎖屏。
   預期 log：`startSilentAudio` → `watchdog started` → 響鈴時 `interruption BEGAN` →
   `recoverPlayback: RECOVERED on attempt N` → `DispatchTimer fired` → `stop AFTER=…` 鈴聲停。
2. **alerting 夾值**：觀察 `alerting NOW — stopAt clamped`（預測 fireDate 偏差時）。
3. **BGTask**：lldb 手動觸發
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.sunnywalker.alarm.autostop"]`
4. **系統自動靜音上限**：>10 分鐘後的鬧鐘、不開 app，計時系統自己停的時間（決定整夜情境要不要加碼）。
5. **回前景不打架**：鬧鐘在 in-app 響時鎖屏再解鎖，確認 AlarmRingView 鈴聲不被
   `endBackgroundLifecycle` 砍掉（已 gate `firingAlarm == nil`）。
6. **沒回應統計**：視窗內不理 → 自動停鈴後開 app，WakeHistory 出現「沒有回應（自動停止）」。
