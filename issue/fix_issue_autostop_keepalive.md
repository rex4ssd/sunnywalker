# Fix — 背景自動停鈴失效（黑標一直響、時間到不消失）

> 日期：2026-06-10
> 狀態：✅ 真機驗證成功（log 見本文第 5 節）
> 相關檔案：`Views/Home/HomeView.swift`、`Services/AlarmAutoStopService.swift`、`SunnyWalkerApp.swift`
> 背景文件：`issue/ALARM_AUTO_STOP.md`（響鈴視窗模型總設計）

---

## 1. 症狀

設 1 分鐘鬧鐘 → 鎖屏、不碰手機 → 鬧鐘響（鎖屏黑標）後**一直響不會自動停**。
過去（約 2026-06-08 前後）時間到黑標會自己消失、自動停鈴；某次改版後壞掉。
不是 force-quit：使用者完全沒動手機，app 只是進背景。

---

## 2. 關鍵診斷：先排除「自動停鈴邏輯壞了」

第一步用 git 證明問題**不在**自動停鈴邏輯本身：

```bash
git diff 00e5292 HEAD -- SunnyWalker/Services/AlarmAutoStopService.swift
# → 空 diff
```

`00e5292` 是 `ALARM_AUTO_STOP.md` 記載「真機驗證成功」的 baseline。`AlarmAutoStopService.swift`
從那一版到現在**逐字相同**。同一份 code 之前會停、現在不停 → 問題在「進背景時的 audio session
處理」被別的修改影響，而不是停鈴邏輯。

對照 HomeView：自 baseline 以來 `scenePhase → background` 分支唯一實質變化，是 issue#2
（關屏沒鈴聲）加進來的「無條件 `setActive(false)`」與 `firingAlarm==nil` guard。

---

## 3. 根因：keep-alive 的 audio session 被 `setActive(false)` 殺掉

自動停鈴是 **100% app-side**——AlarmKit（iOS 26）**沒有原生 ring-duration / timeout API**
（已查 Apple API + WWDC25；`countdownDuration.postAlert` 是貪睡間隔，不是自動停）。
所以「響 N 分鐘自動停」只能靠：

- 進背景時播 **0 音量 `.playback` + `.mixWithOthers`** 的靜音音訊，用 `audio` background mode
  把 app 保活，讓 `DispatchSourceTimer` 在 `stopAt` 精準呼叫 `AlarmKit.stop()`。

失效鏈：

```
scenePhase → inactive：enterBackgroundAlarmMode（async）啟動 keep-alive 靜音 player
scenePhase → background：同 handler 內『同步』跑 try? sess.setActive(false)
   → 把剛啟動的 keep-alive .playback session 關閉（log: prevCategory=…Playback）
   → app 失去 audio background mode → iOS 立刻 suspend
   → stopAt 的 DispatchTimer 被凍結，永遠跑不到 → 黑標永遠不停
（雪上加霜：startSilentAudio 有 guard silentPlayer == nil，第二趟不會重啟）
```

那個 `setActive(false)` 的本意是修 issue#2：殘留的 **麥克風（`.playAndRecord`）** session 會
ducking 掉鈴聲。但它寫成「無條件 tear down 整個 session」，**連自動停鈴要用的 `.playback`
保活 session 一起殺**。`.mixWithOthers` 0 音量的 playback **不會** duck 掉 AlarmKit（SpringBoard
播放）的鈴聲，所以根本不該被關。

> 為什麼 baseline 帶著同一行 `setActive(false)` 卻能停？兩趟 scenePhase 的時序競態：baseline
> 當時 keep-alive 啟動恰好排在最後一次 `setActive(false)` 之後而勝出；現行 iOS / 啟動時序下，
> `setActive(false)` 穩定地壓在 keep-alive 之後把它關掉。屬於「時序相依」的環境退化——修法是
> 讓它不再相依於時序。

---

## 4. 修法：把 `setActive(false)` 改成有條件（gate）

原則：**麥克風一定關**（issue#2 的 ducking 元凶），但**自動停鈴需要的 keep-alive `.playback`
session 不要動**。

### 4.1 `HomeView.swift` — scenePhase → background 分支

```swift
if firingAlarm == nil {
    let sess = AVAudioSession.sharedInstance()
    let prevCat = sess.category
    // 一定先關麥克風/capture（issue#2 的 ducking 元凶就是 .playAndRecord）
    BackgroundListeningManager.shared.stop()
    // ★ 但當 AlarmKit 已授權且有鬧鐘在響鈴視窗內時，不要 deactivate keep-alive 的 .playback session
    if AlarmKitService.shared.isAuthorized,
       AlarmAutoStopService.shared.keepAliveNeededNow() {
        print("🏠 scenePhase → background: stopped mic, KEEPING keep-alive audio session for AlarmAutoStop")
    } else {
        try? sess.setActive(false, options: [.notifyOthersOnDeactivation])
        print("🏠 scenePhase → background: released mic + audio session …")
    }
}
```

### 4.2 `AlarmAutoStopService.swift` — 新增 `keepAliveNeededNow()`

判定邏輯與 `beginBackgroundLifecycle()` 的響鈴視窗一致（single source of truth）：有 armed 鬧鐘
的 fire 時刻落在 `lookAheadMinutes`（10 分）內就回 true。

```swift
func keepAliveNeededNow() -> Bool {
    let now = Date()
    let upcoming = armedAlarms.values.filter { $0.stopAt > now }
    guard !upcoming.isEmpty else { return false }
    let nearestFire = upcoming
        .map { $0.stopAt.addingTimeInterval(-Double($0.ringSeconds ?? 0)) }
        .min()!
    return nearestFire.timeIntervalSince(now) <= lookAheadMinutes * 60
}
```

UN-fallback（AlarmKit 未授權）走 else 照舊 `setActive(false)`，issue#2 的修法完整保留。

---

## 5. 驗證（成功 log 重點行）

```
🏠 scenePhase → background: stopped mic, KEEPING keep-alive audio session for AlarmAutoStop
…（鬧鐘響）
🛡️ AlarmAutoStop.interruption BEGAN (likely AlarmKit ring) — fighting suspension
🛡️ AlarmAutoStop.recoverPlayback: attempt 1 failed — …560557684 Session activation failed
🛡️ AlarmAutoStop.recoverPlayback: RECOVERED on attempt 3 — keep-alive restored
🛡️ AlarmAutoStop.DispatchTimer fired for FACB65DA
🔔 AlarmKitService.stop(FACB65DA) — state BEFORE=alerting
🔔 AlarmKitService.stop(FACB65DA) — state AFTER=scheduled   ← 黑標停了
🛡️ AlarmAutoStop.disarm: FACB65DA — 3 still armed
```

關鍵：keep-alive 在鬧鐘響的瞬間被中斷（560557684 session 競態），但 Layer 2.5 的 interruption
復活在第 3 次重試救回 → app 沒被 suspend → DispatchTimer 在 `stopAt` 觸發 → `stop()` 把
`alerting` 改成 `scheduled`（靜音）。整條鏈如設計運作。

---

## 6. 加進來的診斷工具（lifecycle forensics，🔬 prefix）

為了在「process 在背景被殺、沒有 log」時也能事後重建時間軸，加了持久化鑑識（純 log、不改行為）：

- `recordHeartbeat(phase)`：watchdog 每 5s／keep-alive 啟動／dispatch 觸發／BGTask 各戳一個
  UserDefaults 時間章 → 下次開 app 看「app 背景最後一次還在執行是幾點」。
- BGTask-fired marker、AppDelegate `didEnterBackground` / `willTerminate` marker。
- `logLifecycleForensics(context:)`：開 app（前景／冷啟動／BGTask 喚醒）時印出心跳、BGTask、
  每顆 armed 鬧鐘的 AlarmKit 狀態、UN delivered/pending 數。

> 這次問題既已定位，forensics 可保留當長期黑盒，或日後想精簡時整段移除（搜尋 `🔬`）。

---

## 7. ✅ 附帶發現（已修 2026-06-10）：幽靈鬧鐘讓 watchdog 無限空轉

同一份 log 出現大量：

```
🛡️ watchdog: 1 overdue — stopping
🔔 AlarmKitService.stop(722A79FC) — state BEFORE=not-found    ← 每 5s 一次，永不停
```

注意 `722A79FC` **只印 BEFORE=not-found、從不印 AFTER=**。原因：

```swift
func stop(id: UUID) async throws {
    let before = alarmState(id: id)          // not-found
    try manager.stop(id: id)                 // ← not-found 時 throw，函式在此中止
    let after  = alarmState(id: id)          // never
    AlarmAutoStopService.shared.disarm(id)   // never reached → 永遠 disarm 不掉
}
```

`722A79FC` 是個 AlarmKit 端已不存在（not-found）卻留在 `armedAlarms` 的殘留條目。因為
`manager.stop()` 對 not-found 會 throw，**`disarm()` 永遠執行不到** → watchdog 每 5s 都把它當
overdue → 無限空轉 → keep-alive / watchdog 在背景永不 teardown → **持續耗電**。

### 已採用修法：`stop()` 用 `defer` 保證 disarm（`AlarmKitService.swift`）

```swift
func stop(id: UUID) async throws {
    // disarm 一定要執行——即使 manager.stop() 對 not-found 鬧鐘 throw，否則殘留條目讓 watchdog 無限空轉
    defer { AlarmAutoStopService.shared.disarm(alarmID: id) }
    let before = alarmState(id: id)
    print("🔔 stop(\(id.uuidString.prefix(8))) — state BEFORE=\(before)")
    guard before != "not-found" else {           // AlarmKit 端已不存在 → 只 disarm，不碰會 throw 的 stop
        print("🔔 stop — not-found → disarm only (skip manager.stop)")
        return
    }
    try manager.stop(id: id)
    let after = alarmState(id: id)
    print("🔔 stop — state AFTER=\(after)")
}
```

效果：幽靈條目第一次被 watchdog 掃到就會 `disarm()` 清掉 → 下一個 5s tick 不再 overdue →
spam 停止、背景 keep-alive/watchdog 正常 teardown → app 自然 suspend，不再持續耗電。

> 設計原則：任何「清理殘留登記」的 stop/cancel，cleanup 都要放在 `defer`，不可排在會 throw
> 的呼叫之後。

---

## 8. 一句話總結

自動停鈴邏輯沒壞；是 issue#2 為了防鈴聲被 ducking 而加的「無條件 `setActive(false)`」誤殺了
自動停鈴賴以保活的 keep-alive `.playback` session。改成「只關麥克風、響鈴視窗內保留 keep-alive」
即修復。附帶發現 not-found 幽靈鬧鐘導致 watchdog 無限空轉，建議讓 `stop()` 保證 `disarm()`。
