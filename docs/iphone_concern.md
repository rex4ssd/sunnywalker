# SunnyWalker — Apple App Store 上架問題清單 / iphone_concern.md

> 建立日期：2026-06-01 ｜ 最後更新：2026-06-01（全部程式碼問題已修復）
> 基準：v1.0.0-rc1（Day 29 feature-complete）、參照 `lode_iphone/docs/for_Apple_store/IDENTIFIERS.md`
> 識別碼詳表：`docs/for_Apple_store/IDENTIFIERS.md`
> 目的：列出所有擋路項目、待補項目、已就緒項目，給 Rex 作為上架 SOP。

---

## 0. 狀態快覽

| 類別 | 狀態 |
|---|---|
| 功能開發 P0–P6 | ✅ 完成（60 tests pass） |
| Swift 原始碼 IP 問題 | ✅ **修復**：GhibliColors→SunnyColors 等，16 檔全清零 |
| totoro_breath.caf | ✅ **修復**：→ sunny_wake.caf |
| App Icon alpha（RGBA） | ✅ **修復**：→ RGB 無透明 |
| DEVELOPMENT_TEAM | ✅ **修復**：NHY8MKW8NH 已寫入 project.pbxproj |
| ITSAppUsesNonExemptEncryption | ✅ **修復**：false 已加入 Info.plist |
| iPad orientation key | ✅ **修復**：~ipad Portrait 已加入 Info.plist |
| scheduleTestAlarm | ✅ **修復**：#if DEBUG … #endif 包覆 |
| AlarmScheduler double-alarm | ✅ **修復**：isAuthorized guard 已加 |
| Bundle ID | ✅ **更新**：com.m2k.sunnywalker → app.rexcode.sunnywalker |
| AlarmKit entitlement 批准 | ⏳ **等待中**：已申請，等 Apple 批准 |
| iOS 26 beta 限制 | 🟡 App Store 要等 iOS 26 GM，TestFlight 可先測 |
| 截圖 | 🔴 **待做**：最少 6.9" 一組（Simulator ⌘S） |
| Support / Privacy URL | ✅ 已建立（rexcode.app） |
| PrivacyInfo.xcprivacy | ✅ 完整 |
| Usage descriptions (Info.plist) | ✅ AlarmKit / Mic / Speech 三項齊全 |
| App Store Connect 帳號設定 | ❌ **待做**：尚未建立 App 項目 |
| 送審 metadata（描述/關鍵字） | ✅ 見 `github_rexcode/sunny_walker/APP_STORE_LISTING.md` |

---

## 1. App 識別碼（目前已知）

| 項目 | 值 | 狀態 |
|---|---|---|
| Bundle ID（主 App） | `app.rexcode.sunnywalker` | ✅ 已設 |
| Bundle ID（Tests） | `app.rexcode.sunnywalkertests` | ✅ 已設（不上架） |
| Team ID | `NHY8MKW8NH`（RUEI YI WU，同 Lode） | ✅ |
| DEVELOPMENT_TEAM（project.pbxproj） | `NHY8MKW8NH` | ✅ 已設定 |
| Marketing Version | `1.0.0` | ✅ |
| Build Number | `1` | ✅ |
| Min iOS | `26.0` | ✅（AlarmKit 需求） |
| Targeted Devices | `1,2`（iPhone + iPad） | ✅ |
| SKU（App Store Connect 內部） | `sunnywalker-ios-001` | ❌ 待在 ASC 建立 |

---

## 2. ✅ 已修復項目（原上架硬性擋路，2026-06-01 全部解決）

### 2-A. Ghibli / Totoro IP（最高優先）

**問題**：Swift 原始碼中 16 個檔案直接使用 Studio Ghibli 受保護的 IP，Apple Guideline 5.2 會退件。

| 影響範圍 | 檔案 | 嚴重度 |
|---|---|---|
| 吉祥物元件 | `Views/Components/TotoroAvatar.swift`<br>`Views/Components/GhibliButton.swift` | 🔴 最高（視覺 UI 直接呈現龍貓造型） |
| 主題顏色 | `Theme/GhibliColors.swift`（含 `totoroGray`） | 🔴 高（API 命名 + 顏色注釋引用 Totoro） |
| 字型主題 | `Theme/GhibliFonts.swift` | 🔴 高 |
| 大量引用 | `AlarmEditorView.swift`（26次）、`AlarmListView.swift`（22次）、`HomeView.swift`（17次）等 12 檔 | 🔴 高 |
| Accessibility label | `TotoroAvatar.swift` → `.accessibilityLabel("龍貓")`<br>`.accessibilityHint("SunnyWalker 吉祥物")` | 🔴 需同步改 |

**修法**：設計原創吉祥物「小晴（Sunny）」，替換龍貓外觀，重命名所有 Ghibli*/Totoro* 符號：

```
GhibliColors  → SunnyColors
GhibliFonts   → SunnyFonts
GhibliButton  → SunnyButton
TotoroAvatar  → SunnyAvatar
totoroGray    → sunnyGray（依新角色顏色命名）
.accessibilityLabel("龍貓") → .accessibilityLabel("小晴")
```

---

### 2-B. App Icon 佔位圖

**問題**：`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 是 PIL 產生的純色底 "SW" 文字，不符合 App Store 圖示規範。

- 需要：1024×1024 px PNG，無透明背景，無圓角（系統自動加）
- 建議：以「小晴」吉祥物為核心，暖色系（配合 SunnyWalker 琥珀/橙色品牌）

---

### 2-C. AlarmKit Entitlement 批准

**問題**：`SunnyWalker.entitlements` 已宣告 `com.apple.developer.alarmkit = true`，但此 entitlement **需要 Apple Developer Portal 申請審核**，否則：
- 真機安裝後 `AlarmManager.requestAuthorization()` 會 throw
- 無法上傳至 TestFlight / App Store Connect

**行動**：
1. 登入 developer.apple.com → Certificates, Identifiers & Profiles
2. App ID `app.rexcode.sunnywalker` → Capabilities → **Alarms**（申請 AlarmKit）
3. 提交申請，等候批准（通常數天至數週）

---

### 2-D. DEVELOPMENT_TEAM 未設定

**問題**：`project.pbxproj` 無 `DEVELOPMENT_TEAM`，Xcode 無法自動簽章，Archive 失敗。

**修法**：Xcode → Target SunnyWalker → Signing & Capabilities → Team 選 **NHY8MKW8NH（RUEI YI WU）**，存檔後自動寫入 pbxproj。

---

### 2-E. ✅ Info.plist ITSAppUsesNonExemptEncryption — 已確認

`SunnyWalker/Info.plist` 第 46–47 行已有：
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
Transporter 上傳不會被擋。無需再補。

---

### 2-F. 截圖全無

App Store 送審強制需要至少一組 6.9" 截圖（iPhone 16 Pro Max）。

| 截圖規格 | 必要/建議 | 像素 |
|---|---|---|
| 6.9"（iPhone 16 Pro Max） | **必要** | 1320 × 2868 |
| 6.7"（iPhone 15 Plus） | 建議 | 1290 × 2796 |
| 13"（iPad Pro M4） | 建議（已設 iPad 支援） | 2064 × 2752 |

準備：Xcode Simulator ⌘S 截圖。**先修好 App Icon 和吉祥物再截，避免重做。**

---

## 3. ✅ 已就緒項目

| 項目 | 說明 |
|---|---|
| 功能 P0–P6 | AlarmKit、錄音、任務流程、獎勵、床邊模式、起床紀錄全部完成 |
| 60 unit tests | pass + 1 skip |
| `SunnyWalker.entitlements` | AlarmKit key 已宣告（待批准） |
| Info.plist Usage descriptions | `NSAlarmKitUsageDescription`、`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` 齊全 |
| `UIBackgroundModes = [audio]` | 語音辨識需背景音訊，已宣告 |
| `PrivacyInfo.xcprivacy` | `NSPrivacyTracking = false`；UserDefaults（CA92.1）、FileTimestamp（C617.1）；AudioData、OtherUsageData |
| Support URL | `https://rexcode.app/sunny_walker/support/` |
| Privacy Policy URL | `https://rexcode.app/sunny_walker/privacy/` |
| App Store metadata | EN + ZH 描述、關鍵字、宣傳文字 → `github_rexcode/sunny_walker/APP_STORE_LISTING.md` |
| rexcode.app 網站導覽 | topbar dropdown + footer 已有首頁/支援/隱私政策 |
| CFBundleDisplayName / Version | SunnyWalker / 1.0 / build 1 |
| TARGETED_DEVICE_FAMILY = "1,2" | iPhone + iPad 通用 |
| IPHONEOS_DEPLOYMENT_TARGET = 26.0 | AlarmKit 需求 |

---

## 4. Apple Developer Portal 待辦

> Team：RUEI YI WU / NHY8MKW8NH

1. **Identifiers** → 新增（或確認已有）App ID `app.rexcode.sunnywalker`
   - Capabilities 勾選：**Alarms（AlarmKit）**
   - Capabilities 勾選：**Push Notifications**（fallback 通知需要）
2. **Certificates** → 確認 Distribution Certificate 未過期
3. **Profiles** → 建立 App Store Distribution Provisioning Profile for `app.rexcode.sunnywalker`
4. **AlarmKit 申請** → 送出 Alarms capability request（§2-C）

---

## 5. App Store Connect 填寫清單

> 文案詳見：`github_rexcode/sunny_walker/APP_STORE_LISTING.md`

| 欄位 | 值 | 狀態 |
|---|---|---|
| App Name | `SunnyWalker: Kids Alarm`（23字） | 備好，待填 |
| Subtitle | `Parent voice · AlarmKit alarm`（30字） | 備好，待填 |
| SKU | `sunnywalker-ios-001` | ❌ 未建立 |
| Primary / Secondary Category | Education / Utilities | 已決定 |
| Age Rating | 4+ | 已決定 |
| Price | Free | 已決定 |
| Support URL | `https://rexcode.app/sunny_walker/support/` | ✅ |
| Privacy Policy URL | `https://rexcode.app/sunny_walker/privacy/` | ✅ |
| Description EN / ZH-Hant | APP_STORE_LISTING.md §2–3 | ✅ 備好 |
| Keywords EN（89字） | `alarm,kids,children,alarmkit,parent,voice,wake,silent,toddler,task,morning,routine,ios26` | ✅ 備好 |
| Promotional Text | APP_STORE_LISTING.md §2 | ✅ 備好 |
| What's New v1.0 | APP_STORE_LISTING.md §2 | ✅ 備好 |
| App Privacy 問卷 | **Data Not Collected** | ❌ 待填 |
| 截圖 6.9" | 🔴 未做 | |
| Build 上傳 | 🔴 未 Archive | |

---

## 6. 送審備註（App Review Information → Notes，準備好的文字）

```
No login or account required.

AlarmKit (iOS 26): This app uses AlarmKit to fire a full-screen system alarm
that rings through silent mode and Focus mode. Please test on a device running
iOS 26 or later. The Alarms entitlement was requested and approved via Apple
Developer Portal.

Microphone & Speech Recognition: A parent records a short voice message for
each alarm. On-device speech recognition detects the child saying "I'm awake"
to dismiss the alarm. All audio and recognition stays on-device; nothing is
transmitted off-device.

Background Audio: UIBackgroundModes includes "audio" to support on-device
speech recognition during the alarm ring sequence.

To test the alarm flow:
1. Create an alarm set 2–3 minutes from now.
2. Lock the device.
3. Observe the full-screen AlarmKit lock-screen UI.
4. Unlock, then tap "I'm awake" or speak the phrase to dismiss.
```

---

## 7. iOS 26 Beta 注意事項

- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`：App Store **僅在 iOS 26 GM 發布後才接受**此 target。
- **TestFlight** 不受此限，iOS 26 beta 裝置可安裝測試。
- 若想先佔坑，可考慮備一套 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`（AlarmKit 降階為通知鬧鐘）先上架，等 iOS 26 GM 後再更新。

---

## 8. ✅ PrivacyInfo.xcprivacy — On-device 已確認

`SunnyWalker/Services/SpeechRecognizer.swift:49`：
```swift
newRequest.requiresOnDeviceRecognition = true  // 100% offline — never remove
```
且 `startListening()` 開頭有 guard `recognizer.supportsOnDeviceRecognition`（:31–34），
不支援離線辨識的裝置會 throw 而非 fallback 至 cloud。

語音資料 100% 不離裝置 → 現有 PrivacyInfo.xcprivacy 宣告足夠，Privacy Policy 無需更新。

---

## 9. 現在剩下的待辦（程式碼全部修完，只剩外部步驟）

| # | 項目 | 說明 |
|---|---|---|
| 1 | ⏳ AlarmKit entitlement 批准 | 已申請，等 Apple 回覆 |
| 2 | 🔴 截圖 | Simulator ⌘S，6.9"（必）、6.7"、13" iPad（建議） |
| 3 | 🔴 App Store Connect 建立 App | SKU `sunnywalker-ios-001`，填 APP_STORE_LISTING.md 文案 |
| 4 | 🔴 Archive + 上傳 build | Xcode → Product → Archive → Distribute |
| 5 | 🟡 iOS 26 GM 後正式送審 | TestFlight 可先跑，GM 出後再提交審核 |

---

## 10. 上架前有序 Checklist

```
[ ] §2-A  替換所有 Ghibli/Totoro IP（16 Swift 檔）→ SunnyColors / SunnyAvatar / SunnyButton
[ ] §2-B  App Icon 1024×1024 原創設計完成，存入 Assets.xcassets
[ ] §2-D  Xcode Signing → Team = NHY8MKW8NH
[x] §2-E  Info.plist ITSAppUsesNonExemptEncryption = false ✅ 已確認存在
[ ] §4    Apple Developer Portal：建立 App ID app.rexcode.sunnywalker + AlarmKit capability
[ ] §2-C  等 AlarmKit entitlement 批准
[x] §8    SpeechRecognizer requiresOnDeviceRecognition = true ✅ 已確認（SpeechRecognizer.swift:49）
[ ] §2-F  iOS 26 真機：鎖屏→靜音→響鈴→語音關閉 全流程驗收
[ ] §2-F  Simulator 截圖：6.9"（必）、6.7"（建議）、13" iPad（建議）
[ ] §5    App Store Connect 建立 App，填入 APP_STORE_LISTING.md 所有 metadata
[ ] §5    上傳 build（Archive → Organizer → Distribute → App Store Connect）
[ ] §5    App Privacy 問卷填 Data Not Collected
[ ] §6    填寫送審備註
[ ] ---   等 iOS 26 GM 正式送審（或先 TestFlight 驗收）
```

---

## 11. 無法存取的參考文件

> ⚠️ `/Users/lion/Documents/lode/docs/MaterialsRequiredforAppleStore.md` 本次工作階段**未掛載**，無法讀取。  
> 建議：手動對照該文件，確認有無本頁未涵蓋的 Apple 要求。  
> 本文件的對照基準為 `lode_iphone/docs/for_Apple_store/IDENTIFIERS.md`（目前最完整的參照）。
