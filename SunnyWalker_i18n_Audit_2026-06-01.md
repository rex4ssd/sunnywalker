# SunnyWalker — 全盤檢查 + 中/英雙語化 完工報告
**日期：2026-06-01　機器：Mac Studio M1 Max / macOS Tahoe 26.5 / Xcode 26 / iOS 26 Simulator**

## ✅ 最終狀態
`** BUILD SUCCEEDED **`、可在模擬器執行、設鬧鐘會響且**不再閃退**、卡片可點擊編輯、App 內可即時切換 繁中／English。

---

## 1. 國際化（主要需求：完整 EN + 繁中，含 App 內切換）

| 檔案 | 內容 |
|---|---|
| `SunnyWalker/Localizable.xcstrings`（新增） | String Catalog，**102 組字串**，來源 `zh-Hant`，全附 `en` 翻譯 |
| `Services/Localization.swift`（新增） | `LocalizationManager`（驅動環境 `\.locale`，即時切換不需重啟）＋ 全域 `L()`（給 model／service／通知／AlarmKit 等非 SwiftUI 字串）＋ `LanguagePickerSection` |
| `SunnyWalkerApp.swift` | 根視圖注入 `.environment(\.locale, …)`，切語言時 `Text` 立即重新在地化 |
| `AlarmIOView.swift` | 最上方新增「語言 / Language」區塊（跟隨系統／English／繁中） |
| `project.pbxproj` / `project.yml` | 註冊新檔；`knownRegions` 加入 `en`；部署目標同步為 26.0 |

兩條路徑、同一個選擇：① SwiftUI `Text("字面")`/`Button` 等 → 環境 locale + Catalog 自動翻；② 非 SwiftUI 字串 → `L("key")` 讀對應語言 bundle。

**為在地化做的重構**：`GhibliButton` 改用 `LocalizedStringKey`（原本按鈕文字全漏翻）；`weekdaySymbols`（日→S…）、`responseFormatted`、`methodLabel`、家長題目、匯入結果、錯誤訊息、通知與 AlarmKit 標題、鬧鐘預設名稱「起床囉」等非字面字串全部接上 Catalog。

**語言切換怎麼用**：右下角淺綠色「分享/匯出」鈕 → 通過家長驗證 → 最上方「語言 / Language」。
> 鬧鐘**鎖屏響鈴**的標題跟「裝置語言」走（系統 UI 限制），不受 App 內選單控制。

---

## 2. 效能 / 技術 Bug 修正

**🔴 AlarmKit 整合根本編不過（第一次真機編譯才現形，~22 個 error，全是既有程式問題、非 i18n 造成）**
原因：`AlarmKitService.swift` 照「想像的 API」寫，跟 iOS 26 真實 SDK 對不上，從未編譯成功（orchestrator `_build.log` 是空的）。依 Apple 官方文件＋三篇指南改成真實 API：

- `AlarmConfiguration` → 巢狀型別，改用工廠 `.timer(duration:attributes:…)` 與 `.alarm(schedule:attributes:stopIntent:…)`
- `Alarm.Schedule`（被 SwiftData model `Alarm` 蓋掉）→ 全部限定為 `AlarmKit.Alarm.Schedule.…`
- `AlarmPresentation.Alert.title` 需要 `LocalizedStringResource`（不是 String）→ 已轉換
- `scheduledAlarms` 回傳型別 → `[AlarmKit.Alarm]`；`manager.alarms` 是 throwing property → `(try? …) ?? []`
- `StopAlarmIntent.perform()` → 改 `async throws` 並 `await`（`AlarmManager.stop` 是 async）

**🔴 鬧鐘一響就閃退（崩在 SpringBoard，不是 App）**
崩潰堆疊在 `com.apple.ToneLibrary`／`TLAlertQueuePlayerController`：模擬器播放 **AlarmKit 自訂鈴聲**的已知 bug。→ 移除自訂 `sound:`，改用系統預設鬧鈴音（程式內已標好註解，真機可解開 `sound: .named("totoro_breath.caf")`）。家長錄音仍由 App 內 AVAudioPlayer 播放，不受影響。

**🟠 SpeechRecognizer 跨執行緒**：辨識 callback 在背景佇列直接改 `@Published`／寫 SwiftData → 包進 `DispatchQueue.main.async`，避免閃退。

**🟠 設定一致性**：`project.yml` 部署目標 `17.0` → `26.0`（與 pbxproj、AlarmKit 對齊）。

---

## 3. UX 修正
- **點時間/名稱即可編輯鬧鐘**（原本只有長按選單，且 `swipeActions` 在 ScrollView 內無效）。
- **預設鬧鐘名稱在地化**：卡片用 `LocalizedStringKey(alarm.label)`，預設名「起床囉」英文顯示「Wake up」，客製名稱維持原樣。

---

## 4. 已驗證
build 成功 → 模擬器執行 → 設鬧鐘觸發（log：`AlarmKitService: synced … weekdays=[2,3,4,5,6]`）→ 響鈴不閃退 → 切 English，時間/Wake up/M T W T F 全英文。

## 5. 建議後續（未做，附理由）
1. **滑動刪除**：`AlarmListView` 在 ScrollView+LazyVStack 內，`.swipeActions` 無效；目前刪除走長按選單。要正常左滑刪除需改 `List`（會動到樣式，建議 Xcode 內邊改邊預覽）。
2. **雙重排程**：依你指示舊版 `AlarmScheduler`（本機通知）與 AlarmKit **並存**；真機驗證 AlarmKit 後建議移除舊路徑以免重複提醒。
3. **真機才測得到**：AlarmKit 需 Apple 核准 entitlement；自訂鈴聲、破靜音/鎖屏響鈴都要真機。
4. **鎖屏標題語言**：跟裝置語言走（系統限制）。

## 6. 變更檔案
**新增**：`SunnyWalker/Localizable.xcstrings`、`SunnyWalker/Services/Localization.swift`
**修改（Swift）**：AlarmKitService、StopAlarmIntent、SpeechRecognizer、AlarmScheduler、Alarm、WakeRecord、SunnyWalkerApp、AlarmListView、AlarmRingView、AlarmEditorView、AlarmIOView、ParentalGateView、RecordingView、WakeHistoryView、GhibliButton
**修改（設定）**：`project.pbxproj`、`project.yml`、`scripts/dev.sh`（模擬器自動偵測）
