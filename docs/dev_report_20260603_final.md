# SunnyWalker 收工報告 — 2026-06-03 (Final)

> **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「申請 / 等批准 / portal 開啟 Alarms capability / 解除 entitlements 註解」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。


---

## 本次完成

| 功能 | 說明 |
|------|------|
| FAB 按鈕提示標籤 | 每個圓形按鈕左側加 capsule 文字標籤，多語系 |
| 向左滑刪除鬧鐘 | `ScrollView+LazyVStack` → `List`，swipeActions 生效 |
| 時間滾輪數字看不到 | iOS 26 Liquid Glass 問題，加 `.colorScheme(.light)` 修復 |
| 語音辨識英文模式 | `SpeechRecognizer` 改為 locale-aware，英文用 `en-US` + 英文 keywords |
| 語言切換到主畫面 | FAB 加 Menu，無家長驗證 |
| FAB 標籤多語系失效 | `fabLabel(String)` → `fabLabel(LocalizedStringKey)` |
| 時鐘 12h/24h 統一 | 兩者都改用 `DateFormatter + en_US_POSIX`，不再受 zh_TW locale 干擾 |
| Settings 頁面 | 整合：時鐘格式、語言、錄音間隔、起床紀錄、匯入匯出 |
| 床邊模式兒童鎖 | 移到 Settings 家長專區，開/關都要過 ParentalGate |
| 錄音播放間隔 | `AudioPlayer` 改為 gap loop，可在 Settings 設 0–5 秒 |
| 錄音時自動降音量 | `startSpeechCycle()` 開始時 `duck(0.12)`，結束時 `unduck()` |
| AlarmKit entitlement | comment 掉等 Apple 批准，現走 UNNotification fallback |
| `isAuthorized` 快取問題 | 改用 `_isAuthorized` private flag，不信任 iOS 快取 |
| syncAllEnabled race condition | `onAppear` → `.task(id: alarms.count)` |
| 空 weekdays 鬧鐘沒排 | 加 one-shot UNNotification 路徑 |
| syncAllEnabled 吃掉 fallback | 只 cancel 成功 sync 到 AlarmKit 的 UUID |

---

## 未解（留給下一輪）

### 問題 1：自定錄音不會在鬧鐘一響時播放，要點到 app 才切換

**症狀**：鬧鐘時間到 → 播系統 `.default` 聲 → 用戶點通知開 app → 才播父母錄的聲音。

**根本原因**：
- `UNNotificationSound(named:)` 只能讀 app bundle 或 `Library/Sounds/` 的 `.caf/.aiff/.wav`
- 父母的錄音存在 `Documents/Recordings/<UUID>.m4a`（AAC 格式，不在 bundle）
- 無法在 notification 階段直接播 Documents 裡的檔案

**已確認的解法（未實作）**：
1. 在 `RecordingView` 儲存錄音後，用 `AVAssetExportSession` 把 `.m4a` 轉成 LPCM `.caf`
2. 把轉好的 `.caf` 複製到 `<sandbox>/Library/Sounds/alarm_<alarmUUID>.caf`
3. `AlarmScheduler.schedule()` 改用 `UNNotificationSound(named: "alarm_\(alarm.id.uuidString).caf")`
4. 鬧鐘刪除時一併清掉對應的 `Library/Sounds` 檔案

**關鍵限制**：
- `.caf` 必須是 LPCM / MA4 / µLaw，< 30 秒
- `AVAssetExportSession` 從 AAC→LPCM 需要用 `AVAssetExportPresetAppleM4A` 以外的 preset，或自組 `AVMix`
- `Library/Sounds/` 的檔案在 app 刪除時才清掉，需手動管理

---

### 問題 2：把現有鬧鐘的時間往後調，不會再響

**症狀**：鬧鐘 A 在 14:05 響了 → 用戶進 editor 把時間改到 14:30 → 14:30 不響。

**已知的兩種修法都試過但無效**：

修法 A：`saveAlarm()` 裡直接呼叫 `AlarmScheduler.shared.schedule(alarm: tempAlarm)` ← 有做，理論上應該重排，實測不響。

修法 B：`sheet(isPresented: $showingEditor, onDismiss:)` 加 `syncWithModel(alarm:)` ← 有做，實測不響。

**懷疑的 root cause（未確認）**：
1. `AlarmScheduler.schedule()` 移除舊 notification 後重新排，但新的 `UNCalendarNotificationTrigger` 在當天的「下次」算法可能把今天排過的時間視為「已過」，直接跳到下週同一天。
2. `AlarmKitService.syncAlarm()` 在 edit 後被呼叫，即使 AlarmKit 沒授權，可能有副作用（需 debug log 確認）。

**建議下一輪 debug 步驟**：
1. 加 print：在 `AlarmScheduler.schedule()` 印出 `alarm.hour`, `alarm.minute`, `alarm.weekdays` 和 `center.add(request)` 的結果
2. 在 edit 後呼叫 `center.getPendingNotificationRequests(completionHandler:)` 列出所有 pending notification，確認新時間的 trigger 有沒有被正確排進去
3. 如果有排進去但沒響，問題在 iOS 的 notification delivery（可能是同一天排過就跳下週）
4. 如果沒排進去，問題在 code path（可能是 `isAuthorized` 仍然 true 讓 schedule 直接 return）

---

## 技術債 / 待確認

- `AppSettings.swift` 和 `SettingsView.swift` 是新建的檔案，需在 Xcode 手動 add 到 target（`AppSettings` 用 Add Files 加入，`SettingsView` 已移進 `HomeView.swift` 底部不需額外加）
- AlarmKit entitlement 申請：`developer.apple.com` → 申請 `com.apple.developer.alarmkit` → 批准後解 `SunnyWalker.entitlements` 的 XML comment
- 英文語音辨識需要裝置下載離線英文語音模型（Settings → General → Language → English speech）

---

## 檔案異動清單

```
Modified:
  SunnyWalker/Services/AlarmKitService.swift
  SunnyWalker/Services/AlarmScheduler.swift
  SunnyWalker/Services/AudioPlayer.swift
  SunnyWalker/Services/SpeechRecognizer.swift
  SunnyWalker/Models/Alarm.swift
  SunnyWalker/Views/Home/HomeView.swift          ← 含 SettingsView struct
  SunnyWalker/Views/Alarm/AlarmListView.swift
  SunnyWalker/Views/Alarm/AlarmRingView.swift
  SunnyWalker/Views/Settings/AlarmEditorView.swift
  SunnyWalker/Localizable.xcstrings
  SunnyWalker/SunnyWalker.entitlements

New:
  SunnyWalker/Services/AppSettings.swift          ← 需手動加到 Xcode target
  docs/AlarmKit授權說明.md
  docs/dev_report_20260603.md
  docs/dev_report_20260603_final.md
```
