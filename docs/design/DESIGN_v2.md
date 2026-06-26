# SunnyWalker v2 — 重整設計文件

> 目標：取代 iPhone / iPad 內建鬧鐘，成為「兒童專用」的起床工具。
> 撰寫日期：2026-05-31　|　平台基準：**iOS 26 / iPadOS 26（AlarmKit）**

---

## 0. TL;DR（先讀這段）

內建鬧鐘對小孩不友善的三個痛點，全部源自「它是給成人用的通用工具」。SunnyWalker 的定位要從「又一個鬧鐘 app」轉成 **「一個會把『起床』變成小孩看得懂、做得到的任務的起床夥伴」**。

技術上最大的轉折：**iOS 26 的 AlarmKit** 讓第三方 app 第一次能做出「跟內建鬧鐘一樣可靠」的鬧鐘——突破靜音與專注模式、鎖屏全螢幕呈現、Dynamic Island、自動超時關閉。這是整個 v2 的地基。**v1 用 `UNUserNotificationCenter` 排鬧鐘的做法要全部換掉**，因為它在鎖屏時叫不醒人、也不能突破靜音。

一個必須先接受的現實：基於隱私沙盒，AlarmKit 的「自訂鬧鐘聲」必須放在 App bundle 或 `Library/Sounds/`，而且目前回報自訂聲音可能只播一次、不一定循環。所以「家長錄音當鬧鐘聲整夜循環大響」這條路不穩。**正確架構是混合式**：用 AlarmKit 保證「一定叫得醒」（可靠的系統級響鈴），小孩按下「我起床了」後，再由 App 開到可愛的互動畫面、播放家長錄音、走起床任務。詳見 §3。

---

## 1. 痛點對照：內建鬧鐘 vs SunnyWalker

| 內建鬧鐘的問題 | 對小孩的實際影響 | SunnyWalker v2 的對策 |
|---|---|---|
| iPad 響 10 分鐘、螢幕一直亮、沒按就一直亮 → 很快沒電 | 家長要跑來關、平板整天沒電 | AlarmKit 系統鬧鐘**會自動超時停止**；響鈴 UI 由系統管理，響完即收，不會無限全亮。床邊模式平常極暗，只有響鈴時才亮（§4） |
| 不能自訂聲音 → 小孩不知道鬧鐘代表要做什麼 | 鈴聲對小孩無意義，只是噪音 | 家長錄真人語音「寶貝起床囉，今天要上學」＋鬧鐘**綁定一件具體任務**（上學／睡覺／刷牙），讓聲音＝指令（§3、§5） |
| GUI 不可愛、不直覺，小孩打開不知道要幹嘛 | 小孩看不懂、不會操作 | 吉卜力風格、大圖示、**零文字也能懂**的互動關鬧鐘流程：龍貓引導 →「我起床了」大按鈕 → 完成獎勵（§5、§6） |

---

## 2. 產品定位與使用者

- **主使用者**：3–8 歲兒童（識字前到低年級）。介面以圖像、聲音、動畫為主，文字為輔。
- **設定者（買單者）**：家長。家長負責建立鬧鐘、錄音、設定任務、看孩子的起床紀錄。
- **核心情境（依你的選擇）**：裝置**鎖屏放口袋或桌上**。因此「叫得醒」這件事不能依賴 App 在前景，**必須交給 AlarmKit**。
- **設計準則**：
  1. 小孩端：**無字也能操作**，每個畫面只有一個主要動作。
  2. 可靠優先：先確保「一定會響、一定叫得醒」，可愛是第二層。
  3. 省電優先：螢幕預設不亮，響鈴亮、響完關。

---

## 3. 核心架構：AlarmKit 混合模式

### 3.1 為什麼一定要用 AlarmKit

AlarmKit（iOS 26 新框架）給第三方 app 與內建時鐘相同的能力：即使在靜音 / 專注模式也會響、鎖屏全螢幕的 stop/snooze 畫面、Lock Screen / Dynamic Island / Apple Watch 呈現。這是過去（iOS 18 以前）只有 Apple 時鐘 app 才有的權限；以前第三方只能用 time-sensitive 通知或申請 critical alert entitlement，都做不到「不可能錯過的鬧鐘」。

### 3.2 自訂聲音的限制（必須誠實面對）

- AlarmKit 的自訂聲音 **必須放在 App main bundle 或 `Library/Sounds/`**，讀不到 `Documents/`。
- 已有開發者回報自訂聲音（<30 秒 mp3）**只播一次、不會循環**，行為不如預期穩定。

**結論**：不要把「家長錄音」當成 AlarmKit 的鬧鐘聲去硬撐。

### 3.3 混合式流程（建議架構）

```
[排程] 家長設定鬧鐘
   └─ AlarmManager.shared.schedule(id, configuration)
        ├─ schedule: 相對時間 + 每週重複 (relative + weekly recurrence)
        ├─ sound:   App 內建的溫和但可靠的「叫醒聲」(bundle 音檔)
        └─ presentation: 自訂標題、tint、停止按鈕(綁 App Intent)

[響鈴] 時間到（即使鎖屏 / 靜音）
   └─ 系統顯示 AlarmKit 全螢幕鬧鐘 UI（突破靜音、自動超時）
        └─ 小孩按「我起床了！」(stop 按鈕)
             └─ 觸發我們的 App Intent → 開啟 App

[互動] App 進入「起床任務」畫面（前景，這時才需要前景）
        ├─ 播放家長錄音（從 Documents 讀，想循環就循環）
        ├─ 顯示這個鬧鐘綁定的任務（上學／睡覺…）
        └─ 完成任務 → 獎勵動畫 → 收工
```

要點：
- **可靠的「叫醒」由 AlarmKit + bundle 聲音負責**（鎖屏、靜音都成立）。
- **可愛的「家長語音 + 互動」由 App 前景負責**，在小孩按下停止、App 被叫起來之後才跑——這時播 Documents 裡的錄音完全沒問題，也不受 AlarmKit 聲音限制。
- AlarmKit 的 stop 按鈕可綁 App Intent 執行自訂程式碼；secondary 按鈕可設成 `.countdown`（貪睡）或 `.custom`。

### 3.4 關鍵 API（iOS 26）

```swift
import AlarmKit

// 1) 權限（Info.plist 需加 NSAlarmKitUsageDescription）
let manager = AlarmManager.shared
switch manager.authorizationState {
case .notDetermined:
    let granted = (try? await manager.requestAuthorization()) == .authorized
case .authorized: break
case .denied:     break          // 引導家長去設定開啟
@unknown default: break
}

// 2) 排程（每週重複的早晨鬧鐘）
let time = Alarm.Schedule.Relative.Time(hour: 7, minute: 30)
let recurrence = Alarm.Schedule.Relative.Recurrence.weekly([.monday, .tuesday, .wednesday, .thursday, .friday])
let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))

let alert = AlarmPresentation.Alert(
    title: "起床囉！",
    stopButton: AlarmButton(text: "我起床了", textColor: .white, systemImageName: "sun.max.fill")
)
let attributes = AlarmAttributes<WakeMetadata>(
    presentation: AlarmPresentation(alert: alert),
    tintColor: .orange
)
let config = AlarmConfiguration(schedule: schedule, attributes: attributes /*, sound: 內建音檔 */)
try await manager.schedule(id: alarm.id, configuration: config)
```

> 註：以上為依官方文件與多份開發者教學整理的骨架，實作時以 Xcode 中 AlarmKit 的實際簽名為準（API 在我寫作時仍屬較新框架）。

---

## 4. 螢幕與省電策略（對應你的選擇：響鈴亮、響完關）

1. **AlarmKit 原生超時**：系統鬧鐘 UI 由系統管理，會自動結束，不會像內建那樣「沒人按就一直全亮」拖垮電量。這直接解掉 iPad 整天沒電的痛點。
2. **床邊模式（App 前景時）**：
   - 平常顯示**極暗**的夜間時鐘畫面（深色背景、低亮度、可選只顯示一隻睡著的龍貓）。
   - `UIApplication.shared.isIdleTimerDisabled` 僅在「正在響鈴互動」期間設為 true，互動結束立刻設回 false，避免長亮。
   - 善用 iOS 26 的待命（StandBy）/ Live Activity 呈現，讓「插電當床頭鐘」也省電。
3. **完成即收**：小孩完成起床任務 → 播放短獎勵動畫 → 自動降低亮度 / 退出全亮畫面。

---

## 5. 功能重整

### 5.1 鬧鐘 = 聲音 + 一件事（核心創新）
每個鬧鐘綁定一個「任務卡」，讓鈴聲對小孩有意義：

- 預設任務模板：上學、睡覺、刷牙、收玩具、喝水、午睡起床。
- 每個任務有：大圖示 + 家長錄音 +（可選）一句話。
- 小孩看到的不是「07:30 鬧鐘」，而是「上學囉」＋媽媽的聲音。

### 5.2 家長錄音（保留並強化）
- 錄音存 `Documents/Recordings/`，在「互動畫面」播放（不受 AlarmKit 聲音限制）。
- 建議錄音規格：單聲道、16–24kHz、~32kbps AAC/Opus，10 秒約 40KB（省儲存、利日後雲端分享）。
- 多個鬧鐘可共用同一段錄音；錄音與鬧鐘解耦（v1 用 alarm.id 當檔名會導致無法共用，需改成獨立 VoiceClip id）。

### 5.3 互動關鬧鐘（取代「滑動關閉」）
- 主流程：龍貓動畫引導 → 一顆大大的「我起床了！」→ 完成。零文字可懂。
- 進階（可選、家長開關）：說出「我起床了」用 `SFSpeechRecognizer` 離線辨識才能關（適合大一點、賴床的孩子）。**注意**：語音辨識只能在 App 前景跑，所以它是「互動畫面裡的加強關卡」，不是「叫醒」機制本身。

### 5.4 起床紀錄與獎勵
- 連續起床天數、貼紙 / 集點、龍貓造型解鎖 → 給小孩正向回饋。
- 家長端可看「這週幾點起床、是否需要叫第二次」。

### 5.5 Markdown 匯入 / 匯出（已完成，需小幅調整）
- 已實作 `Services/MarkdownAlarmIO.swift` + `Views/Settings/AlarmIOView.swift`。
- v2 調整：格式增加「任務類型」欄位，例如 `weekdays, 07:30, 上學, school`。

---

## 6. 介面架構（小孩看得懂為最高原則）

- **小孩首頁**：滿版場景（依時間變化的天空）＋龍貓＋下一個鬧鐘的大圖示。沒有列表、沒有設定按鈕。
- **響鈴互動畫面**：龍貓 + 任務圖示 + 一顆主按鈕。
- **家長區**（需長按 + 簡單手勢/數字鎖進入，避免小孩誤改）：鬧鐘列表、錄音、任務設定、紀錄、訂閱、匯入匯出。
- 全程大圖示、強對比、語音輔助；文字一律可被圖示取代。

---

## 7. 資料模型調整（SwiftData）

```
Alarm
  id, hour, minute, weekdays[], isEnabled, label
  taskType: enum(school/sleep/brush/...)          // 新增：鬧鐘綁定的任務
  voiceClipID: UUID?                               // 改：指向 VoiceClip，不再用 alarm.id 當檔名
  alarmKitID: UUID                                 // 新增：對應 AlarmKit 排程 id
VoiceClip
  id, name, fileName, duration                     // 與 Alarm 解耦，可共用
WakeRecord                                         // 新增：起床紀錄
  id, alarmID, firedAt, dismissedAt, neededSecondCall
```

---

## 8. 商業模式（重點摘要，非投資建議）

- **預設全本機、零雲端成本**：私人錄音留在裝置，只有使用者主動上傳分享才進雲端。
- **省成本三招**：壓縮音檔（人聲 ~32kbps）、用 egress 便宜的物件儲存（如 R2）、設長度/數量上限並做內容審核。
- **收費建議走標準 freemium，而非「不付錢就強制公開」**：
  - 免費：完整鬧鐘功能 + 有限自訂錄音數。
  - 付費：私有雲端備份 / 跨裝置同步 / 無限錄音 / 更多龍貓造型。
  - 社群聲音庫改成「**自願投稿換獎勵**」（胡蘿蔔），而不是「不付費就被迫公開」（棍子）——在親子市場評價更安全。
- **兒少安全紅線**：**兒童語音預設絕不公開**到開放網路；公開素材以成人語音或去識別化為主。注意 COPPA / GDPR-K 等兒少隱私法規。

---

## 9. 風險與待確認

| 風險 | 說明 | 緩解 |
|---|---|---|
| AlarmKit 自訂聲音限制 | 只能放 bundle/Library、可能只播一次 | 採混合架構（§3.3），錄音放互動畫面播 |
| API 較新 | AlarmKit 是 iOS 26 才有，簽名可能微調 | 以 Xcode 實際簽名為準；最低支援版本設 iOS 26 |
| 僅支援 iOS 26+ | 舊機型用不到 | 評估市場；或為舊版保留「弱化版」通知鬧鐘 |
| 語音辨識僅前景 | 不能當叫醒機制 | 定位為互動畫面的加強關卡 |
| 兒童語音公開的法規/輿論風險 | 隱私與兒少安全 | 預設私有、嚴格審核、成人語音優先 |

---

## 參考資料（Sources）

- [iOS 26 Makes Third-Party Alarm and Timer Apps Better — MacRumors](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)
- [Wake up to the AlarmKit API — WWDC25, Apple Developer](https://developer.apple.com/videos/play/wwdc2025/230/)
- [AlarmKit — Apple Developer Documentation](https://developer.apple.com/documentation/AlarmKit)
- [Scheduling an alarm with AlarmKit — Apple Developer Documentation](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit)
- [AlarmPresentation — Apple Developer Documentation](https://developer.apple.com/documentation/alarmkit/alarmpresentation)
- [Scheduling and Managing Alarms in SwiftUI with AlarmKit — Create with Swift](https://www.createwithswift.com/scheduling-and-managing-alarms-in-swiftui-with-alarmkit/)
- [Scheduling Alarms in iOS Apps with AlarmKit: A Complete Guide — Manav (Medium)](https://medium.com/@manavmanuprakash/scheduling-alarms-in-ios-apps-with-alarmkit-a-complete-guide-88b727f1c523)
- [AlarmKit play sound only once — Apple Developer Forums](https://developer.apple.com/forums/thread/807752)
