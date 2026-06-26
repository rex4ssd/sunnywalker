# SunnyWalker 開發日誌 — 2026-06-03

> **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「申請 / 等批准 / portal 開啟 Alarms capability / 解除 entitlements 註解」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。


> 本次 session 從 UI bug 開始，一路挖到 AlarmKit entitlement、iOS 26 Liquid Glass、
> UNNotification 聲音消失、語音辨識語言鎖死等根本問題。

---

## 一、完成功能

### 1. FAB 按鈕功能提示標籤
- **問題**：右下角四顆圓形按鈕沒有任何文字說明，用戶不知道功能。
- **做法**：`HomeView.addButton` 每個 Button 包一層 `HStack`，左側加 `fabLabel(_ key: LocalizedStringKey)` capsule 標籤。標籤走 xcstrings 自動多語系。
- **檔案**：`HomeView.swift`

### 2. 鬧鐘聲音（完整流程修正）
- **最終架構**：AlarmKit entitlement 未批准 → 強制走 UNNotification + `.default` 系統通知聲。
- **做法**：
  - `AlarmScheduler.swift`：`content.sound = .default`（移除依賴 `sunny_wake.caf`）
  - `AlarmKitService.swift`：`_isAuthorized` 私有旗標，只有 `requestAuthorization()` 成功才設 true
  - `AlarmKitService.syncAllEnabled()`：只取消已成功 sync 到 AlarmKit 的 UNNotification，失敗的保留作 fallback
  - `AlarmScheduler.schedule()`：補上空 weekdays 的一次性鬧鐘路徑
  - `HomeView.swift`：`onAppear` → `.task(id: alarms.count)` 解決 @Query race condition
  - `SunnyWalker.entitlements`：把 `com.apple.developer.alarmkit` 用 XML comment 包起來（等 Apple 批准再解）

### 3. 時間滾輪數字看不到（iOS 26 Liquid Glass）
- **問題**：`DatePicker(.wheel)` 在 `WatercolorCard`（接近白色背景）上，iOS 26 adaptive color 讓數字跟背景同色。
- **做法**：加 `.colorScheme(.light)` 強制深色文字。
- **檔案**：`AlarmEditorView.swift`

### 4. 向左滑動刪除
- **問題**：`swipeActions` 只在 `List` 內有效，原本用 `ScrollView + LazyVStack` 完全不作用。
- **做法**：`AlarmListView.body` 換成 `List`，加 `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + `.listRowBackground(Color.clear)` 維持原視覺。
- **檔案**：`AlarmListView.swift`

### 5. 編輯鬧鐘時間後不叫
- **問題**：AlarmEditorView 存檔後沒有重新排程的保證。
- **做法**：`.sheet(isPresented: $showingEditor, onDismiss:)` 加 `AlarmScheduler.shared.syncWithModel(alarm:)`，確保 dismiss 後一定重排。
- **檔案**：`AlarmListView.swift`（AlarmCard）

### 6. 語音辨識 English 模式失效
- **問題**：`SpeechRecognizer` 硬寫 `zh-TW` locale + 中文關鍵字，英文說 "I'm awake!" 永遠不會觸發。
- **做法**：`init()` 讀 `SunnyLocalization.code`，切換 recognizer locale 和 keywords：
  - `en` → `en-US` + `["I'm awake", "I am awake", "I'm up", "wake up", "awake"]`
  - 其他 → `zh-TW` + `["我起床了", "好的", "知道了", "起床囉"]`
- **檔案**：`SpeechRecognizer.swift`

### 7. 語言切換移到主畫面
- **做法**：FAB 最上方加 Menu，直接切三種語言（跟隨系統 / English / 繁體中文），無家長驗證。
- FAB 標籤改 `LocalizedStringKey` 讓 xcstrings 翻譯生效（解決英文模式仍顯示中文標籤的問題）。
- **檔案**：`HomeView.swift`

### 8. Settings 頁面統一整合
- **新增** `SettingsView.swift`：
  - 時鐘格式（12h / 24h toggle）
  - 語言切換 Picker
  - 播放間隔 Stepper（0–5 秒）
  - 家長專區：起床紀錄 + 匯入/匯出（進入才跳 ParentalGate）
- 主頁 FAB 移除獨立的「起床紀錄」和「匯入/匯出」按鈕，統一進設定。
- **新增** `AppSettings.swift`：`use24HourClock`、`recordingGapSeconds` 存 UserDefaults。

### 9. 12h / 24h 時間格式統一
- **問題**：主頁時鐘用 `.dateTime.hour().minute()`（跟裝置 locale），鬧鐘卡片用 `"%02d:%02d"`（固定 24h），兩者不一致。
- **做法**：
  - `Alarm.formattedTime(use24h:)` 新增方法
  - `AlarmCard` 用 `AppSettings.shared.use24HourClock`
  - `ClockHeaderView` 用 `settings.use24HourClock` 切換 `FormatStyle`
- 預設值：自動偵測裝置 locale 的 hour cycle。

### 10. 錄音播放音量 + 間隔
- **問題**：錄音連續播放（`numberOfLoops = -1`），音量大，小孩說話被蓋過去。
- **做法**：
  - `AudioPlayer.swift` 全重寫：`numberOfLoops = 0`，delegate 裡等 `recordingGapSeconds` 秒再播
  - 間隔期間完全靜音 → 小孩說話窗口
  - `startSpeechCycle()` 開始時 `audioPlayer.duck(to: 0.12)`，結束後 `unduck()`
- **檔案**：`AudioPlayer.swift`、`AlarmRingView.swift`

---

## 二、修復的 Bug

| # | 症狀 | Root Cause | 修法 |
|---|------|-----------|------|
| 1 | 鬧鐘完全沒聲音（第一次） | AlarmKit `sound:` 全部被 comment 掉，Simulator 沒有 AlarmKit 聲音 | `#if targetEnvironment(simulator)` 條件編譯，真機加回 `sound:` |
| 2 | Build 失敗：entitlement not found | `com.apple.developer.alarmkit` 沒有 Apple 批准就放進 entitlements | 用 XML comment 包起，等批准再啟用 |
| 3 | `isAuthorized` 永遠回 true，UNNotification 沒排到 | iOS 快取 AlarmKit auth 狀態，即使 entitlement 移除仍顯示 authorized | 改用 `_isAuthorized = false`，只有 `requestAuthorization()` 成功才設 true |
| 4 | `syncAllEnabled` 顯示 0/0 | `@Query` race condition：`onAppear` 比 SwiftData 載入早 | `onAppear` → `.task(id: alarms.count)` |
| 5 | AlarmKit 失敗後 UNNotification 也不見 | `syncAllEnabled` 把所有 UNNotification 取消，不管 AlarmKit 成不成功 | 只取消已成功 sync 的 UUIDset |
| 6 | 一次性鬧鐘（空 weekdays）無聲 | `for weekday in []` 零次迴圈，沒排任何 notification | 加 `alarm.weekdays.isEmpty` 分支，用 non-repeating trigger |
| 7 | English 模式說話沒反應 | SpeechRecognizer hardcode `zh-TW` | locale-aware init |
| 8 | FAB 標籤英文模式還是中文 | `fabLabel(_ text: String)` 用 String 不是 LocalizedStringKey | 改 `fabLabel(_ key: LocalizedStringKey)` |

---

## 三、錯誤嘗試 / 踩到的雷

### 3.1 以為 `sunny_wake.caf` 在子目錄造成 UNNotificationSound 無聲
- **誤判**：`UNNotificationSound(named:)` 只找 bundle root，以為 `.caf` 在 `Theme/Sounds/` 子目錄
- **實際**：pbxproj 裡是 file reference（非 folder reference），Xcode Copy Bundle Resources 會壓平到 bundle root
- **更後來發現**：真正原因根本不是檔案位置，是 AlarmKit entitlement 問題
- **浪費**：改了 sound fallback 邏輯，後來確認音效檔格式完全正確（mono LPCM 44.1kHz 18秒）

### 3.2 以為 `sunny_wake.caf` 是 stereo 需要轉換
- **誤判**：第一次 Python 分析 CAF 格式時，讀 `desc` chunk 的 offset 搞錯，誤以為是 2ch stereo
- **實際**：重新解析後確認是 1ch mono，不需要轉換
- **浪費**：試了 `afconvert`（bash 沒有），又寫了 Python 轉換腳本，最後無用

### 3.3 以為 iPhone 14 Plus 截圖是真機
- **誤判**：以為「Settings → Alarms: ON」截圖和「AlarmKit banner 沒聲音」截圖是同一台真機
- **實際**：「有 banner 沒聲音」是 **iPhone 14 Plus Simulator**（Simulator 的 AlarmKit 不發聲）
- **後果**：花了大量時間在 Simulator 上 debug AlarmKit 聲音，Simulator 本來就不支援

### 3.4 以為 AlarmKit `sound:` 不指定會用系統預設聲
- **假設**：省略 `sound:` 參數 → AlarmKit 用系統鬧鐘聲
- **實際**：iOS 26 AlarmKit 省略 `sound:` = **完全靜音**（已在真機驗證）
- **修法**：加 `#if targetEnvironment(simulator)` 然後在 `#else` 補 `sound: .named("sunny_wake.caf")`

### 3.5 `manager.authorizationState == .authorized` 不可信
- **假設**：`authorizationState` 反映實際 entitlement 狀態
- **實際**：iOS 把使用者的「Alarms: ON」設定快取起來，即使 entitlement 已從 binary 移除仍回 `.authorized`
- **後果**：`AlarmScheduler` 看到 `isAuthorized = true` → 不排 UNNotification；`syncAlarm` 有 entitlement → 也 throw → 完全沒有鬧鐘

### 3.6 試圖在 Simulator 測試 AlarmKit 聲音
- 反覆測試都是 "0/0 synced to AlarmKit" 加上 Simulator crash
- 根本原因：Simulator 不支援 AlarmKit 真正的排程和聲音播放
- **教訓**：AlarmKit 功能只能在真實裝置上驗證

---

## 四、架構決策

| 決策 | 選擇 | 放棄的選項 | 原因 |
|------|------|-----------|------|
| AlarmKit entitlement | comment 掉，等 Apple 批准 | 強制移除所有 AlarmKit code | 保留 code，批准後只需解 comment |
| 鬧鐘聲音 | UNNotification `.default` | 自訂 `.caf` 音效 | `.default` 保證有聲，`.caf` format 在某些狀況 silent fail |
| 時鐘格式切換 | `AppSettings` + UserDefaults | SwiftData Model | 不需跨裝置同步，UserDefaults 足夠 |
| 錄音播放間隔 | `AVAudioPlayerDelegate` + Task | `DispatchQueue.asyncAfter` | Task 可以被 cancel（stop() 時乾淨結束） |
| 語音辨識語言 | `SpeechRecognizer.init()` 讀 locale | 傳入參數 | AlarmRingView 用 @StateObject，init 時 locale 已確定 |

---

## 五、待辦 / 已知限制

- [ ] AlarmKit entitlement 向 Apple 申請（`com.apple.developer.alarmkit`）→ 批准後解 comment `SunnyWalker.entitlements` 裡的 key
- [ ] AlarmKit 批准後需把 `sound: .named("sunny_wake.caf")` 在 `syncAlarm()` 三處全部解注釋
- [ ] `sunny_wake.caf` 目前僅作為 in-app AudioPlayer 播放音源；UNNotification 走 `.default`
- [ ] Simulator 上 AlarmKit banner 出現但無聲 → 預期行為，非 bug
- [ ] `SpeechRecognizer` 要求 `supportsOnDeviceRecognition`：若使用者裝置無離線英文辨識模型（需在 Settings 下載）則 fallback 到按鈕模式
- [ ] 英文語音辨識關鍵字目前固定，未來可讓家長在 Settings 自訂 wake phrase
