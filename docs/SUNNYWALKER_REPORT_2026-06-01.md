# SunnyWalker — 工作報告 2026-06-01

> **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「申請 / 等批准 / portal 開啟 Alarms capability / 解除 entitlements 註解」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。


## 本次 Session 完成項目

### 1. App Store 上架資料建立（rexcode.app）

| 檔案 | 說明 |
|---|---|
| `github_rexcode/sunny_walker/APP_STORE_LISTING.md` | App Store 完整上架資料，含 EN/ZH metadata、雙 Build 架構、兒少合規、送審備註、checklist |
| `github_rexcode/sunny_walker/support/index.html` | Apple 送審必填 Support URL 頁面（中英雙語） |
| `github_rexcode/sunny_walker/privacy/index.html` | Apple 送審必填 Privacy Policy URL 頁面（COPPA/GDPR-K 合規，中英雙語） |
| `github_rexcode/_layouts/page.html` | SunnyWalker topbar 改 dropdown（首頁/支援/隱私政策），footer 補同三項連結 |

送審 URL：
- Support：`https://rexcode.app/sunny_walker/support/`
- Privacy：`https://rexcode.app/sunny_walker/privacy/`

### 2. rexcode.app Lode iPhone 導覽確認

Lode iPhone topbar dropdown（EN + 中文版）早已有：iPhone / iPad 首頁、iPhone 支援、iPhone 隱私政策，三項皆完整，不需修改。

### 3. SunnyWalker 網站 Ghibli IP 移除

`github_rexcode/sunny_walker/index.md` 替換完成：

| 原文 | 替換後 |
|---|---|
| 龍貓（5 處） | 小晴 |
| Totoro（5 處） | Sunny |
| 吉卜力風格動畫 | 原創角色動畫 |
| 吉卜力互動 | 小晴互動 |
| Ghibli-style animation | original character animation |
| Ghibli interactions | Sunny interactions |

grep 驗證：0 筆殘留。

### 4. iphone_concern.md 建立

`SunnyWalker/docs/iphone_concern.md` — App Store 上架完整問題清單，包含：識別碼、6 項硬性擋路、已就緒項目、Apple Developer Portal 待辦、App Store Connect 填寫清單、送審備註全文、iOS 26 beta 注意事項、PrivacyInfo 待確認項目、有序 checklist。

### 5. AlarmScheduler double-alarm 修復

`SunnyWalker/Services/AlarmScheduler.swift` 加入：
```swift
guard !AlarmKitService.shared.isAuthorized else { return }
```
當 AlarmKit 已授權時，舊 UNNotification 路徑自動讓步，避免審核員看到同一鬧鐘響兩次。

---

## Commits

| Repo | Commit | 說明 |
|---|---|---|
| github_rexcode | `738f705` | sunny_walker: APP_STORE_LISTING + support/privacy pages |
| github_rexcode | `f56b864` | page.html: SunnyWalker topbar dropdown + footer links |
| SunnyWalker | `05e7975` | docs: iphone_concern + fix AlarmScheduler double-alarm |

> `github_rexcode/sunny_walker/index.md`（Ghibli IP）的 commit 因 HEAD.lock 卡住未完成。
> 請在 terminal 執行：
> ```bash
> rm -f '/Users/lion/Documents/github_rexcode/.git/HEAD.lock' '/Users/lion/Documents/github_rexcode/.git/index.lock'
> cd /Users/lion/Documents/github_rexcode
> git add sunny_walker/index.md
> git commit -m "sunny_walker: replace Ghibli/Totoro IP refs with original char 小晴 (Sunny)"
> ```

---

## 尚未完成 — 上架前仍需處理

### Swift 原始碼（最大工程量）

16 個 Swift 檔案仍有 Ghibli/Totoro IP，161+ 行 code-level 引用：

| 類型 | 檔案 | 程式碼引用數 |
|---|---|---|
| 吉祥物 | `TotoroAvatar.swift`、`GhibliButton.swift` | 9、7 |
| 主題 | `GhibliColors.swift`、`GhibliFonts.swift` | 1、1 |
| View | `AlarmEditorView`（26）、`AlarmListView`（22）、`WakeHistoryView`（16）、`RecordingView`（16）、`HomeView`（15）、`AlarmRingView`（10）、`RewardView`（12）、`ParentalGateView`（10）、`DaytimeScene`（6）、`WatercolorCard`（6）、`CloudBackground`（2） | — |
| Animation | `Animations.swift` | 2 |

需要的改名：`GhibliColors→SunnyColors`、`GhibliFonts→SunnyFonts`、`GhibliButton→SunnyButton`、`TotoroAvatar→SunnyAvatar`、`totoroGray→sunnyGray`。

### `totoro_breath.caf` 音效檔

- 路徑：`SunnyWalker/Theme/Sounds/totoro_breath.caf`
- 仍在 bundle 內，檔名含 IP
- `AlarmKitService.swift` comment 內有 `sound: .named("totoro_breath.caf")`
- 修法：改名為 `sunny_wake.caf`，同步更新 comment

### App Icon 有 alpha 透明（RGBA）

- App Store Connect 拒絕含 alpha 的 1024px icon
- 需重出為 RGB（無 alpha），Xcode Simulator → Export 或 Preview 另存

### DEVELOPMENT_TEAM 未設（無法 Archive）

Xcode → Target SunnyWalker → Signing & Capabilities → Team = `NHY8MKW8NH`

### Info.plist 缺 ITSAppUsesNonExemptEncryption

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 截圖全無

最少需要 iPhone 6.9"（1320×2868）一組。先修好 IP + Icon 再截。

### Info.plist 補 iPad orientation

```xml
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
  <string>UIInterfaceOrientationPortrait</string>
</array>
```

### UILaunchScreen UIColorName 是空字串

建議填入 Asset Catalog 顏色名（避免啟動白閃）。

### scheduleTestAlarm() 確認不可從 UI 觸達

`AlarmKitService.swift` line 109 有 60 秒測試計時器，建議用 `#if DEBUG` 包起來。

### AlarmKit entitlement — 需 Apple 批准（外部步驟）

已宣告 `com.apple.developer.alarmkit = true`，需在 developer.apple.com 申請 Alarms capability 批准。

---

## 下一步建議順序

```
1. Swift IP 重命名（GhibliColors→SunnyColors 等，16 檔）
2. totoro_breath.caf → sunny_wake.caf
3. App Icon 重出 RGB 無 alpha
4. Xcode Signing DEVELOPMENT_TEAM = NHY8MKW8NH
5. Info.plist 補 ITSAppUsesNonExemptEncryption + iPad orientation
6. scheduleTestAlarm() 用 #if DEBUG 包
7. Apple Developer Portal 申請 AlarmKit entitlement
8. 真機驗收 AlarmKit 全流程
9. Simulator 截圖 × 3 尺寸
10. App Store Connect 建立項目，填 APP_STORE_LISTING.md 文案，上傳 build
```
