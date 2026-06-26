> **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「entitlement 還沒批 / 等 Apple 批 / uncomment entitlement / portal 開啟 capability」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。

> **2026-06-04 已更新 — 部分內容已被取代。** 本報告描述的是「AlarmKit 尚未生效、UN 為 fallback」的當日狀態。隔天發現關屏不響的真因是 **AlarmKit 從未被簽進 binary**（`project.yml` 沒設 `CODE_SIGN_ENTITLEMENTS`、`NSAlarmKitUsageDescription` 被移除），已啟用 AlarmKit 並修好。**現況以 `fix_report_2026-06-04_enable_alarmkit.md` 為準**；下方「AlarmKit 還沒批 / UN 是 fallback / 長期才推 AlarmKit」等說法已不適用。

---

# SunnyWalker — 三個鬧鐘 Bug 修復報告

**日期：** 2026-06-03
**接手自：** session `sunnay_0603`（撞到 1M context 額度錯誤中斷，留下兩個未修 bug，本次再加一個）

---

## 修好的三個 bug

### 1. 自定聲音一開始沒聲音，要點進 app 才變自定（檢查 2 次）

**Root cause**
AlarmKit 用 `sound: .named(soundFileName)` 排程，但 `soundFileName` 永遠是 bundled 的 `sunny_wake.caf`。
家長的自訂錄音存成 `Documents/Recordings/<uuid>.m4a` — AlarmKit / UNNotification **讀不到 `.m4a`，也讀不到 Documents**，只認 app bundle 或 `Library/Sounds/` 裡的 `.caf/.aiff/.wav`。
所以鎖屏響的是預設音，只有點進 app 後 `AlarmRingView` 的 `AVAudioPlayer` 才播 `.m4a` 自訂錄音。

**修法**
- 新增 `AlarmSoundExporter`（放在既有的 `AudioRecorder.swift`，避免新檔沒進 Xcode target 的雷）：用 `AVAudioFile` 把 `.m4a` 轉 16-bit PCM `.caf`，寫到 `Library/Sounds/alarm_<uuid>_<epoch>.caf`。
  - 檔名帶 epoch：system sound server 會用檔名 cache 音檔，重錄若沿用同名會重播舊錄音 → 用唯一名避開。
  - cap 30 秒（iOS 對鬧鐘/通知音本來就截 30s），並清掉同一鬧鐘的舊 caf。
- `RecordingView.stopRecording()` 轉檔後設 `alarm.soundFileName = <caf>`；`AlarmEditorView.saveAlarm` 的 `syncAlarm` 重排時就會用自訂音，鎖屏立即響自訂聲。
- app 內仍播全長 `.m4a`（loop + gap），鎖屏播 30s caf —— 雙軌不衝突。
- caf 只在**真機**分支傳給 AlarmKit；Simulator 分支照舊省略 sound（避開 ToneLibrary crash 的舊雷）。

### 2. 相同鬧鐘叫完，把時間往後調就不響了

**Root cause**
AlarmKit **不會 re-arm 一個已經 fired + stopped 的 id**。alarm 進 terminal 狀態後，用同一個 id 再 `manager.schedule()` 會被靜默忽略（same-id upsert 只對 pending 的有效，terminal 的不行）。

**修法**
`AlarmKitService.syncAlarm()` 在 schedule 前先 `try? await manager.cancel(id: alarm.id)` 清掉舊 entry，再重新排程 → 重新 arm。

### 3. 關屏時鬧鐘響，解鎖鐘就停了

**Root cause**
路由漏掉「背景喚醒」這條路。`HomeView.onAppear` 只跑一次；`StopAlarmIntent` 用 `NotificationCenter.post(.alarmFired)` 是 ephemeral —— app 從鎖屏背景被喚回前景時 run loop 還沒 active，post 丟失 → `AlarmRingView` 沒出現、鈴就停。

**修法**
- `StopAlarmIntent` 一律把 alarmID 寫進 `UserDefaults` `pendingAlarmKitAlarmID`（已有）。
- `HomeView.checkPendingAlarm` 改成同時讀 `AppDelegate.pendingAlarmID` **和** `UserDefaults`，消費後兩邊都清。
- 加 `@Environment(\.scenePhase)`，`onChange == .active` 時重跑 `checkPendingAlarm`；`.task(id: alarms.count)` load 完也補跑一次（順手解 `@Query` race）。
- `onReceive(.alarmFired)` 也清掉 UserDefaults marker，避免下次 resume 誤觸重響。
- 前景中的 app 仍走 NotificationCenter fast path，幾條路徑彼此 idempotent。

---

## 改動檔案（全部都是既有檔，不需新增 Xcode target membership）

| 檔案 | 改動 |
|------|------|
| `Services/AudioRecorder.swift` | 新增 `AlarmSoundExporter`（m4a→caf） |
| `Views/Settings/RecordingView.swift` | 存檔後設 `soundFileName` 指向 caf |
| `Services/AlarmKitService.swift` | `syncAlarm` schedule 前先 cancel |
| `Views/Home/HomeView.swift` | scenePhase 路由 + UserDefaults 消費 + task 重試 |

3 條新雷已寫回 Vein（`project:sunnywalker`）：`77d0` 自訂音 caf、`aecc` terminal id 不 re-arm、`6d65` 背景喚醒路由。

---

## 還沒做 / 真機驗證清單

1. **無法在這裡編譯**（iOS app 要在你 Mac 上 build）。AVAudioFile / scenePhase API 我已逐行手動核對，但請在真機跑過。
2. 前一個 session 留下的 `Services/AppSettings.swift` 是新檔 —— build 前先 `xcodegen generate`（`project.yml` 是 `- path: SunnyWalker` 整夾 glob，會自動納入），否則會 "Cannot find 'AppSettings' in scope"。
3. **三個 bug 都要真機測**（AlarmKit + 自訂音 Simulator 測不準，舊雷）：
   - bug1：錄自訂音 → 鎖屏等鬧鐘 → 第一聲就該是自訂音。
   - bug2：讓鬧鐘響完 → 編輯同一顆把時間往後調 → 應該還會響。
   - bug3：關屏 → 鬧鐘響 → 解鎖按 stop → app 應跳出起床畫面並繼續播錄音。

---

# 第二輪修正（2026-06-03 下午）— 看了實機截圖後

**關鍵發現：截圖那個「黑色橫幅 + X」是一般 UNNotification，不是 AlarmKit 全螢幕鬧鐘。**
代表這台機器 **AlarmKit 根本沒在跑**（entitlement 還沒批 → `requestAuthorization` 失敗 → `isAuthorized=false`），真正在響的是 `AlarmScheduler`（舊 UNNotification 路徑）。
→ **第一輪我改的 AlarmKit `.named(caf)` 在這台是死的**，難怪沒效。

### 修正 A — 自訂聲音（點黑標才變自定）
真路徑 `AlarmScheduler` 寫死 `content.sound = .default`。改成：有自訂錄音時用 `UNNotificationSound(named: soundFileName)`，指向匯出的 `Library/Sounds/alarm_*.caf`。
- `HomeView.task`：AlarmKit 未授權時改用 `AlarmScheduler.syncWithModel` 重排所有 alarm（原本完全沒人在 launch 重排 UN，舊 alarm 永遠用舊的 .default）。
- `AlarmScheduler.schedule` 加 self-heal：有 recordingName 但 soundFileName 還是 default → 當場 export caf。**舊錄音不用重錄也會自動補。**

### 修正 B — 聲控失效（root cause 找到了）
上一版 `AudioPlayer` 的 gap-loop 改版，讓 `startOnce()` **每次 loop 都重設 `AVAudioSession` 為 `.playback`**。
而 `SpeechRecognizer` 需要 `.playAndRecord` 收麥克風——錄音一 loop（幾秒後）session 被打回 `.playback`，**麥克風當場斷掉**，聲控永遠 match 不到 → 跑到 fallback。
→ 修法：`AVAudioSession` 只在 `AudioPlayer.play()` 設**一次**，`startOnce()`（loop 重播）絕不碰 session；並用 `currentVolume` 在 loop 間保留 duck 音量。

### 修正 C — 全鏈路診斷 log（你要的）
每個關鍵點都加了帶 emoji 前綴的 print，Xcode console 可直接 filter：
`` 通知排程/觸發 · `` AppDelegate launch · `` HomeView 路由 · `` AlarmRingView 起音 · `` AudioPlayer/session · `` 語音辨識
追一次鬧鐘流程，把這幾行貼回來就能定位卡在哪。

### 改動檔案（第二輪）
| 檔案 | 改動 |
|------|------|
| `Services/AlarmScheduler.swift` | 自訂 caf 聲音 + self-heal + log |
| `Services/AudioPlayer.swift` | session 只設一次（修聲控）+ 保留 duck + log |
| `Views/Home/HomeView.swift` | 未授權時重排 UN 路徑 + 路由 log |
| `SunnyWalkerApp.swift` / `AlarmRingView.swift` / `SpeechRecognizer.swift` | 診斷 log |

新增 2 條 Vein 雷：`5860`（AlarmKit dormant → 真路徑是 UN）、`3ee2`（AudioPlayer loop 重設 session 殺麥克風）。

### 真機測試重點
1. **先確認走哪條路徑**：看 console `AlarmKitAuthorized=` 那行。`false` = UN 路徑（目前狀態）。
2. **自訂聲音**：進該鬧鐘**重存一次**（觸發 self-heal/重排）→ 等鬧鐘 → 第一聲橫幅就該是自訂音。console 應出現 `... using CUSTOM banner sound`。若橫幅變**靜音**（caf fall through）回報我，改回 default。
3. **聲控**：點橫幅進 app → 等 5s 開始聽 → 說「我起床了」。console 看 `listening` 後**不該**馬上斷；錄音 loop 後仍能 match。
4. AlarmKit 全螢幕鬧鐘要等 Apple 批 entitlement 才會生效，那才是長期解；在那之前 UN 是 fallback。

---

# 第三輪 — 黑標鈴聲還是預設，全鏈路插 log 查斷點（2026-06-03 傍晚）

**先講清楚架構（這是你觀察到「開 app=自定、移背景=預設」的原因）：**
這是**兩條完全獨立的聲音路**——
- **app 內**：`AlarmRingView` 的 `AVAudioPlayer` 播 `Documents/Recordings/*.m4a`（自定）。
- **黑標**：`UNNotification` 的 `content.sound`，由系統在背景播。

`UNNotificationSound(named:)` 找不到檔 / 格式不對 / 超過 30 秒，會**靜默 fallback 成預設鈴**，不報錯——所以最難查。已把整條路插滿 log。

**加了哪些 log（Xcode console filter 用）：**
- `Exporter:` — m4a 來源是否存在、大小；caf 是否寫出、大小、失敗原因。
- `AlarmScheduler:` — 選了什麼聲音、`existsInLibrarySounds=` caf 在不在、`Library/Sounds contents=` 整夾列表。
- `AppDelegate.willPresent / didReceive:` — 鬧鐘**實際 fired 當下** content.sound 是什麼 + identifier。

**請這樣測一次，把 / 開頭那幾行貼回來：**
1. 進那顆「REx'費得瑞」鬧鐘 → **重新存一次**（觸發 export + 重排）。
2. 把鬧鐘設 1 分鐘後 → 切到背景 → 等黑標響。
3. console 會出現三段關鍵 log，一看就知道斷在哪：
   - `Exporter: SOURCE m4a MISSING` → 錄音實體檔對不到（recordingName 問題）。
   - `existsInLibrarySounds=false` → caf 沒成功產生。
   - caf 在、但 `willPresent content.sound` 還是 default → 是 iOS 嫌格式/長度 → 下一步改成**直接錄 caf**（不走 m4a 轉檔）。

**一個 OS 硬限制要先知道：** 黑標（一般通知）**在背景無法開麥克風**。所以「黑標下直接聲控停鬧鐘」用 UNNotification 是做不到的，一定要點進 app 才有錄音/聲控。要在鎖屏/背景直接聲控，只有 **AlarmKit 全螢幕鬧鐘**做得到，而那要等 Apple 批 entitlement。這不是 bug，是路徑本身的限制。

---

# 第四輪 — 現況確認 + commit（2026-06-03 傍晚）

**實機結果：**
- **黑標自定聲音：成功**（移到背景，黑標響的就是家長自訂錄音，不再是預設鈴）。
- app 內聲控停鬧鐘：正常（點進 app 後說「我起床了」可停）。
- **黑標/鎖屏下無法直接聲控** → 要點黑標進 SunnyWalker 才有錄音/聲控（按 X 是退出 app）。

**這個 不是 bug，是 iOS 平台限制：**
> **任何 app 都不能從背景通知啟動麥克風。** 聲控辨識**一定**要 app 在前景才能跑。
> 不論走 UNNotification 還是 AlarmKit，小孩都得先讓 app 到前景（點黑標 / 點 AlarmKit stop），麥克風才會開。沒有繞過的方法。

**log 看不到的原因：** 截圖開在 Issue Navigator（編譯警告）。runtime log 在底部 **Debug Console**（`⌘⇧C`），filter 打 ``/``/``。

## 下一步可選方向（給 Rex 決定）

1. **維持現狀（UN 路徑）**：自定聲音已 OK，黑標一點就進起床畫面聲控。最省事，現在就能用。
2. **推 AlarmKit entitlement**（長期最佳）：鎖屏全螢幕鬧鐘、繞過靜音/專注模式、聲音更穩。但聲控**仍需**點 stop 把 app 帶到前景才開麥克風（這點 AlarmKit 也一樣）。差別只在「鎖屏響鈴體驗」更像系統鬧鐘。
3. **UX 折衷**：黑標點進來時，直接全螢幕 `AlarmRingView` + 5 秒後自動聽——把「點一下→聲控」的路徑做到最短。

## 已知編譯警告（非本次改動造成，未處理）
- `AlarmKitService`: `Result of call to 'schedule(id:configuration:)' is unused`、`No 'async' operations occur within 'await'`、`fireDate` 可改 `let`。
- `BedSideManager`: `UIScreen.main` 在 iOS 26 deprecated。
- `Localization`: `storageKey` actor-isolated（Swift 6 會變 error）。
- 這些都是 warning，不影響 build（已成功跑在 Mr.R iPhone15p）。要清的話可另開一輪。

---

# 第六輪 — 貪睡模式 + 去掉提示詞 1/3 + 新 App icon（2026-06-03 晚）

### 1. 提示詞拿掉「1/3」
改 `Localizable.xcstrings` 的 `attempt_counter` 值，移除 `— try %lld/3`，只剩「說我起床了！」/「Say "I'm awake!"」。（key 仍帶 `%lld`，多餘參數被 `String(format:)` 忽略，不用動 code。）

### 2. 每顆鬧鐘「貪睡模式」（必須打開 App 才能停）
- `Alarm.requireAppToStop`（optional Bool，遷移安全；`effectiveRequireAppToStop`）。`AlarmEditorView` 加勾選 + 說明。
- 機制：打勾的鬧鐘，除了主通知，`AlarmScheduler` 另排一串 **nag 連發通知**（下次發生 +1…+N 分，N = min(響鈴時長, 9)，壓在 iOS 64 則上限內）。在通知按 只關掉那一則，下一分鐘的 nag 又響 → **逼你打開 App**。
- 一打開 App（`AlarmRingView.onAppear`）就 `cancelNags()`：只刪 nag、不刪主鬧鐘（重複鬧鐘明天照響）。
- 不打勾＝原行為，即停。
- 限制：重複鬧鐘的 nag 只排「下次發生」，靠 App 下次開啟 re-arm 續期（每天會開 App 就沒問題）。

### 3. 新 App icon（拿掉 SW 字）
用 PIL 4× 超取樣畫日出場景（太陽＋光芒＋雲＋綠色小丘，暖色漸層，**無文字**），輸出 RGB 無 alpha 1024×1024（App Store 規定不能有 alpha），已覆蓋 `AppIcon-1024.png`。

### 改動檔案（第六輪）
| 檔案 | 改動 |
|------|------|
| `Localizable.xcstrings` | attempt_counter 去掉 1/3 |
| `Models/Alarm.swift` | requireAppToStop + effective |
| `Views/Settings/AlarmEditorView.swift` | 貪睡模式 Toggle + 存檔 |
| `Services/AlarmScheduler.swift` | nag 連發 + cancelNags + nextOccurrence |
| `Views/Alarm/AlarmRingView.swift` | onAppear cancelNags |
| `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 新 icon |

測試重點：貪睡模式鬧鐘 → 響時在通知按 → 應該下一分鐘又響；打開 App 完成起床任務 → 才真的停。普通鬧鐘 即停不變。
