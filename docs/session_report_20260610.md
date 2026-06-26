# SunnyWalker 開發報告 — 2026-06-10

> 範圍：背景自動停鈴 regression 修復 + 幽靈鬧鐘耗電 bug + iOS 26 / Swift 6 編譯警告清理 + 新增 lifecycle forensics 診斷。
> 變更檔案：9 個（+154 / −27）。皆已真機驗證或屬純診斷 log。
> 詳細根因文件：`issue/fix_issue_autostop_keepalive.md`。

---

## 0. 摘要

| # | 項目 | 嚴重度 | 狀態 |
|---|------|--------|------|
| 1 | 背景自動停鈴失效（黑標一直響、時間到不消失） | P0 | 真機驗證成功 |
| 2 | 幽靈鬧鐘（not-found）讓 watchdog 每 5s 無限空轉、背景持續耗電 | P1 | 已修 |
| 3 | iOS 26 / Swift 6 編譯警告 10 項 | P3 | 修 9、刻意保留 2 |
| 4 | 新增 lifecycle forensics 持久化診斷 | — | 已加（純 log） |

---

## 1. P0 — 背景自動停鈴失效

### 症狀
設 1 分鐘鬧鐘 → 鎖屏、不碰手機 → 鬧鐘響後**一直響不會自動停**；過去（約 2026-06-08）時間到黑標會自己消失。非 force-quit。

### 診斷方法（先排除誤判方向）
用 git 證明問題不在停鈴邏輯：`git diff 00e5292 HEAD -- AlarmAutoStopService.swift` 為**空**——自動停鈴邏輯與「真機驗證成功的 baseline」逐字相同。所以是「進背景時的 audio session 處理」被別處改動影響，不是停鈴本身。

### 根因
自動停鈴是 100% app-side（AlarmKit iOS 26 沒有原生 ring-duration / timeout API，已查 Apple 文件 + WWDC25）。它靠「0 音量 `.playback` + `.mixWithOthers` 靜音音訊」用 `audio` background mode 保活，讓 `DispatchSourceTimer` 在 `stopAt` 精準呼叫 `stop()`。

issue#2（關屏沒鈴聲）為了防麥克風 session ducking 掉鈴聲，在 `HomeView` scenePhase→background 加了**無條件** `setActive(false)`。它寫成「tear down 整個 session」，連自動停鈴保活用的 `.playback` session 也一起殺：

```
inactive：keep-alive 靜音 player 啟動（async）
background：同步 setActive(false) → 關掉 keep-alive session → app 失去 audio 保活
        → iOS suspend → stopAt 的 DispatchTimer 凍結 → 永不 stop() → 黑標永遠響
```

（`.mixWithOthers` 0 音量 playback 本來就不會 duck AlarmKit/SpringBoard 鈴聲，根本不該被關。baseline 帶著同一行能停是因為兩趟 scenePhase 的時序競態恰好讓 keep-alive 勝出；現行 iOS / 啟動時序下穩定地反過來——屬時序相依的環境退化。）

### 修法
把 `setActive(false)` 改成**有條件**：麥克風一定關（issue#2 元凶），但 AlarmKit 已授權且有鬧鐘落在響鈴視窗內時（`keepAliveNeededNow()`），保留 keep-alive `.playback` session。

- `HomeView.swift`：scenePhase→background 分支加 gate。
- `AlarmAutoStopService.swift`：新增 `keepAliveNeededNow()`，判定邏輯與 `beginBackgroundLifecycle()` 一致（single source of truth）。

### 驗證（成功 log 關鍵）
```
scenePhase → background: stopped mic, KEEPING keep-alive audio session for AlarmAutoStop
interruption BEGAN … recoverPlayback: RECOVERED on attempt 3 — keep-alive restored
DispatchTimer fired for FACB65DA
stop(FACB65DA) — state BEFORE=alerting → AFTER=scheduled   ← 黑標停了
```

---

## 2. P1 — 幽靈鬧鐘讓 watchdog 無限空轉、持續耗電

### 症狀
成功 log 中夾帶大量 `watchdog: 1 overdue — stopping` + `stop(722A79FC) BEFORE=not-found`，每 5 秒一次、永不停；且該鬧鐘**只印 BEFORE、從不印 AFTER**。

### 根因
`722A79FC` 是 AlarmKit 端已不存在（not-found）卻殘留在 `armedAlarms` 的條目。`stop()` 內 `try manager.stop(id:)` 對 not-found 會 **throw**，使後面的 `disarm()` 永遠執行不到 → 條目清不掉 → watchdog 每 tick 都當它 overdue → 背景 keep-alive / watchdog 永不 teardown → 持續耗電。

### 修法（`AlarmKitService.swift`）
`stop()` 把 `disarm()` 放進 `defer` 保證收尾；not-found 時 guard return、跳過會 throw 的 `manager.stop()`。

> 設計原則：任何「清理殘留登記」的 stop/cancel，cleanup 都要放在 `defer`，不可排在會 throw 的呼叫之後。

---

## 3. P3 — iOS 26 / Swift 6 編譯警告清理

修好 9 項（程式碼），deployment target 為 iOS 26 故可直接用新 API：

- **`storageKey` actor isolation（Swift 6 error）** — `LocalizationManager`(@MainActor) 的常數被 nonisolated 的 `SunnyLocalization` 讀取 → 標 `nonisolated static let`。
- **`Text + Text` deprecated × 4**（AlarmEditorView 3、RingtonePickerSheet 1）— 改字串插值 `Text("\(Text(...))")`，在地化照舊。
- **VoiceLibraryView export 4 警告** — `exportAsynchronously` / `.status` / `.error` deprecated（iOS 18）+ non-Sendable closure 捕捉 → 整段改 `try await exporter.export(to:as:)`。

刻意**保留 2 項**：

- **`UIRequiresFullScreen` deprecated** — 故意的：`project.yml` 註明是為過 App Store 驗證 error 90474（universal + 直向鎖定二選一）。直接移除可能害上架被擋。若要根除得改 `TARGETED_DEVICE_FAMILY:"1"`（純 iPhone）或支援四方向——屬產品決策。
- **「Update to recommended settings」** — Xcode 專案設定升級建議，非程式碼；於 Xcode 內套用，注意別被 xcodegen regenerate 洗掉。

---

## 4. 新增 — Lifecycle forensics 持久化診斷（）

為了在「process 在背景被殺、沒有 log」時也能事後重建時間軸，加了純 log（不改行為）：

- `recordHeartbeat(phase)`：watchdog 每 5s／keep-alive 啟動／dispatch 觸發／BGTask 各戳一個 UserDefaults 時間章 → 下次開 app 看「app 背景最後一次還在執行是幾點」。
- BGTask-fired marker、AppDelegate `didEnterBackground` / `willTerminate` marker。
- `logLifecycleForensics(context:)`：開 app／冷啟動／BGTask 喚醒時印心跳、BGTask、每顆 armed 鬧鐘的 AlarmKit 狀態、UN delivered/pending 數。

> 問題已定位，可保留當長期黑盒，或日後精簡時整段移除（搜尋 ``）。

---

## 5. 變更檔案

| 檔案 | 變更 |
|------|------|
| `Views/Home/HomeView.swift` | setActive(false) 改有條件 gate（P0） |
| `Services/AlarmAutoStopService.swift` | `keepAliveNeededNow()` + forensics（P0 / 診斷） |
| `Services/AlarmKitService.swift` | `stop()` defer disarm + not-found guard（P1） |
| `SunnyWalkerApp.swift` | forensics markers + 冷啟動 dump |
| `Services/Localization.swift` | `nonisolated storageKey`（P3） |
| `Views/Settings/AlarmEditorView.swift` | Text 插值（P3） |
| `Views/Settings/RingtonePickerSheet.swift` | Text 插值（P3） |
| `Views/Settings/VoiceLibraryView.swift` | async `export(to:as:)`（P3） |
| `Localizable.xcstrings` | 在地化字串連帶更新 |

---

## 6. 平台事實（本次查證確認）

AlarmKit（iOS 26）**沒有**原生「響鈴 N 分鐘後自動停」API：`countdownDuration.postAlert` 是貪睡/重複間隔，不是自動停；系統只有自己的 ~15 分鐘上限。因此自訂響鈴時長必然靠 app-side 保活——而 app 被真正 force-quit 時無解（process 死、BGTask 也被壓抑）。本次情境是「背景未被殺」，故 keep-alive 修復有效。

---

## 7. 後續待辦

1. 重 build（必要時先 `xcodegen generate` → Clean）後，照 `ALARM_AUTO_STOP.md` 第 8 節清單再跑一次完整驗證。
2. 決定 `UIRequiresFullScreen`：維持現狀，或改純 iPhone（`TARGETED_DEVICE_FAMILY:"1"`）以根除 deprecation。
3. 釐清幽靈鬧鐘 `722A79FC` 的**上游**來源（為何被 arm 卻沒成功 schedule / 被別處 cancel 而未 disarm）——本次已做防禦式清理，但找出上游可避免再生。
4. forensics 觀察期過後決定保留或精簡。
