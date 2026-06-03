# 設計筆記：背景/鎖屏聲控停鬧鐘可行性

**日期：** 2026-06-03
**起因：** Rex 指出 recorder app（橘色麥克風指示燈長亮）能在背景持續錄音，質疑「背景無法錄音」的說法。

---

## 結論先講：可行，但有分界

Apple 官方限制（已查證）：

> **背景錄音只能「延續」一個在前景啟動的 audio session，不能從背景「啟動」它。**
> 只要 App 在前景開好 `.record`/`.playAndRecord` session 並持續錄音/播放，帶著 `UIBackgroundModes: audio` 進背景就會**繼續執行不被 suspend**；一旦停止錄/播，系統就把它 suspend。

所以：
- ✅ recorder app 能背景錄 = 使用者**在前景**按下「開始錄音」，session 一路活著（橘點長亮）。
- ❌ 被 suspend 的 App **不能**靠「local notification 一響」就啟動麥克風。

→ SunnyWalker 要免點聲控，**必須在前景就開好錄音 session，並讓它一路活到鬧鐘響**。沒有捷徑能在睡著後才從零啟動麥克風。

---

## 兩種實作層級

### Tier 1 — 前景常駐（簡單、零風險，建議先做）
**床邊模式 = App 留在前景**（螢幕亮著但壓暗）。前景下麥克風/聲控本來就能跑，不需任何背景技巧。
- 優點：零 App Review 風險、實作最簡單（床邊模式已存在，只要確保不進背景 + 防自動鎖定 `UIApplication.shared.isIdleTimerDisabled = true`）。
- 缺點：螢幕整夜亮著（壓到最暗 + 黑底可接受，OLED 機耗電有限）。

### Tier 2 — recorder-pro 式背景常駐（螢幕可關，代價高）
睡前在前景啟動 `.playAndRecord` session（裝 tap、buffer 直接丟棄不存檔），帶 `UIBackgroundModes: audio` 進背景，**整夜保持 session 活著**；鬧鐘時間到時 App 仍在背景存活 → 大聲播鬧鈴 + 把 `SFSpeechRecognizer` 接到已活著的音訊 → 免點聲控。
- 關鍵：session **絕不能停**，否則 App 被 suspend。整夜持續「錄音中」。
- 代價/風險：
  1. **橘色麥克風指示燈整夜長亮** → 對一個**兒童 App**，App Review 會嚴格質疑「為何整夜錄音」。Kids Category 對資料蒐集規範更嚴，即使 100% on-device 也可能被打回。**這是最大阻礙，不是技術。**
  2. **耗電**：麥克風 + audio engine 開 8 小時。
  3. `SFSpeechRecognizer` 不適合連續跑數小時（為短語設計）→ 作法是「engine/session 整夜活著、但只在鬧鐘時間才 attach 辨識」。
  4. 記憶體壓力大時系統仍可能回收 App。
  5. 無法全自動：家長**每晚都要開 App 啟動「聆聽模式」**（因為 session 一定要從前景起）。

---

## 建議
1. **先做 Tier 1**：床邊模式強制前景 + 禁自動鎖定，聲控立刻可用、零風險。多數「放床頭」情境這樣就夠。
2. **Tier 2 當進階選項**，且務必：明確的隱私說明、on-device 辨識、清楚告知家長「聆聽模式會整夜使用麥克風」、上架前先跟 App Review 溝通用途。先當實驗功能，別當預設。
3. 長期鎖屏鬧鈴體驗仍建議 **AlarmKit**（等 entitlement），但注意：AlarmKit 也**不能**背景開麥克風，它的 stop 一樣要把 App 帶到前景才有聲控。

---

---

## 已實作（2026-06-03，預設安全）

### 1. 鬧鐘響鈴時長（已啟用）
- `AppSettings.alarmRingDurationMinutes`（1–10 分，預設 5）。
- `AlarmRingView`：onAppear 開 `isIdleTimerDisabled=true` 保持螢幕亮；到時 `handleAutoStop()` → 停音訊/語音 + `isIdleTimerDisabled=false`（讓螢幕休眠省電）+ dismiss。
- Settings → 「響鈴時長」Stepper。

### 2. 背景聆聽聲控（已實作，**Settings 預設關**）
- `AppSettings.backgroundListeningEnabled`（預設 `false`）。
- `BackgroundListeningManager`（在 `AudioRecorder.swift`，免新檔 target 問題）：
  - `start()` 前景啟動 `.playAndRecord` keep-alive engine（tap 丟棄 buffer）→ 背景保活、橘點長亮。
  - 5 秒 timer 偵測鬧鐘時間到 → `beginFiring`（**僅在 app 背景時**自己響，前景交給 AlarmRingView，避免雙 engine 衝突）→ 播鬧鈴 loop + 跑 on-device wake-word 辨識 → 聽到關鍵字就停；到響鈴時長自動停。
  - `SFSpeechRecognizer` 約 1 分鐘上限 → 響鈴期間自動 restart。
- `HomeView`：`syncBackgroundListening()` 推 alarm 快照 + 依開關 start/stop；`firingAlarm` 出現時 stop（讓 AlarmRingView 用麥克風），dismiss 後 resume。
- Settings → 「背景聲控（實驗）」Toggle + 橘點/耗電警告。
- `UIBackgroundModes: audio` 已在 `project.yml`，無需改 Info.plist。

### ⚠️ 已知 caveat（實驗功能，測試時注意）
1. **雙重響鈴**：背景聆聽自己響的同時，原本的 UNNotification 也會響（沒停掉通知）。要單一聲源的話，之後可在 enabled 時不排通知——但那樣聆聽失敗就完全沒鬧鐘，風險自負。
2. **錄音衝突**：聆聽中（engine 在跑）又去錄新鬧鐘音（AVAudioRecorder）可能打架。建議錄音前先關「背景聆聽」。
3. **App Review**：橘點整夜長亮、兒童 App always-on mic，上架審核風險高，先當 local 實驗。
4. 背景 on-device 辨識在實機才測得準（Simulator 不準）。

## Sources
- [AVAudioSession.record — Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
- [AVAudioSession.playAndRecord — Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- [Configuring your app for media playback — Apple](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- [Microphone background service — Apple Developer Forums](https://developer.apple.com/forums/thread/106415)
- [Setting Background Modes in iOS Apps — getstream.io](https://getstream.io/blog/ios-background-modes/)
