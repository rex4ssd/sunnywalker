# SunnyWalker — Session Report 2026-06-04

> 🔴 **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「entitlement 還沒批 / 等 Apple 批 / uncomment entitlement / portal 開啟 capability」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。


## 一、App Store 上架前置審查

本次開工前先做了一輪 App Store 準備狀況掃描，確認以下問題：

| 嚴重度 | 項目 |
|---|---|
| 🔴 必修 | AlarmKit entitlement 仍在 comment — 真機已批准，需 uncomment 並 rebuild |
| 🔴 必修 | SettingsView 兩份（HomeView.swift inline vs 獨立檔），獨立版未進 build target |
| 🔴 必修 | Privacy usage description 只有中文（NSMicrophoneUsageDescription 等） |
| 🟡 待辦 | 截圖（iPhone 6.9" 必填）、隱私政策 URL、年齡分級問卷 |
| ✅ 已 OK | App icon 1024×1024 RGB 無 alpha、ITSAppUsesNonExemptEncryption = false |

---

## 二、新功能開發

### 2-1 錄音管理頁面（新建）

**新檔案：** `Views/Settings/VoiceLibraryView.swift`

- `VoiceClipLimits` enum：`maxCount = 5`、`maxDurationSeconds = 5.0`（兩個常數都加了升級路徑注釋）
- `VoiceLibraryView`：`@Query` 撈 VoiceClip（新到舊），空狀態、clip 列表、新增按鈕（滿 5 個 disable）
- `VoiceClipRow`：播放/暫停（`.symbolEffect(.pulse)`）、名稱 + 時長 + 日期、刪除（confirmationDialog 確認）
- `VoiceClipRecorderSheet`：5 秒倒數圓環、時間到自動停止、錄完後可命名 + 試聽 + 儲存；取消時清掉未完成的 .m4a

**配套修改：**
- `SunnyWalkerApp.swift` — modelContainer 加入 `VoiceClip.self`（之前未掛，@Query 會撈不到）

### 2-2 鈴聲選擇器（新建）

**新檔案：** `Views/Settings/RingtonePickerSheet.swift`

- 兩段式列表：內建音效（☀️ 陽光起床 / 🍃 樹葉沙沙）+ 我的錄音（VoiceClip library）
- 每項可預聽，已選項右側顯示 ✅
- 選 VoiceClip 時自動呼叫 `AlarmSoundExporter.exportLockScreenCAF` → 寫入 `soundFileName`
- `AlarmEditorView` 新增「鈴聲」列（在關鬧鐘方式之前），`ringtoneDisplayKey: LocalizedStringKey` 確保多語言

### 2-3 長頸鹿主題

**新檔案：**
- `Views/Components/GiraffeAvatar.swift` — 純 SwiftUI shapes，黃色身體 + 棕色斑點 + 長頸 + ossicone 角 + 眨眼動畫
- `Views/Components/MascotView.swift` — 根據 `AppSettings.mascotTheme` 切換 SunnyAvatar / GiraffeAvatar

**配套修改：**
- `AppSettings.swift` — 新增 `MascotTheme` enum（`.sunny` / `.giraffe`）+ `@Published mascotTheme` UserDefaults 持久化
- SettingsView — 新增「主題」section，Picker 選擇吉祥物
- 全站 `SunnyAvatar()` → `MascotView()`（HomeView × 3、AlarmRingView、RewardView、RecordingView、VoiceLibraryView）

---

## 三、UX 改版（03_todo_fectures.md）

| 項目 | 修改內容 |
|---|---|
| Language 從 Settings 移除 | 首頁已有 🌐 按鈕，Settings 內的 Language section 刪除 |
| 家長識別移到 Settings 按鈕 | 點齒輪 → ParentalGate → 才開 SettingsView；SettingsView 內所有 sub-gate 全部移除，BedSide 直接 toggle |
| 錄音管理移到第一列 | 移出家長專區，放在 List 最頂端獨立 Section |
| 主頁鬧鐘列麥克風 icon 移除 | `AlarmCard` 只剩 toggle，錄音統一走 Settings → 錄音管理 |

---

## 四、Bug 修正（screenshot review）

| Bug | 修法 |
|---|---|
| TextField 文字看不到 | 加 `.foregroundStyle(SunnyColors.nightIndigo)` + `.colorScheme(.light)`，避免 Liquid Glass 主題干擾 |
| 背景聲控整夜佔用麥克風 | `scenePhase → .active` 才 start mic；`.inactive`/`.background` 立刻 stop。footer 說明也同步更新 |

---

## 五、i18n 全面補完

### Localizable.xcstrings — 29 個 key 補齊 EN 翻譯

| 類別 | Key 範例 |
|---|---|
| Settings labels | 主題→Theme、聲控模式→Voice Control、吉祥物→Mascot |
| 主題名稱 | 長頸鹿→Giraffe、小晴（灰色精靈）→Sunny (Forest Spirit) |
| 錄音管理 | 錄音管理→Recordings、新增錄音→New Recording、選擇鈴聲→Choose Ringtone |
| 動作按鈕 | 停止→Stop、試聽→Preview、儲存→Save |
| 鈴聲名稱 | 陽光起床→Sunny Wake、樹葉沙沙→Rustling Leaves |
| 格式字串 | `clips_counter %lld %lld`→Used %lld / %lld recordings |
| Footer 長文 | 背景聲控 footer、錄音管理 empty state 等 |

### 程式碼修正（繞過 xcstrings 的地方）

| 位置 | 問題 | 修法 |
|---|---|---|
| SettingsView 主題 Picker | `Label(theme.displayName, ...)` 傳 String，不走翻譯 | 改 `Text(LocalizedStringKey(theme.displayName))` |
| VoiceLibraryView 計數器 | `"已使用 \(N) / \(M) 個錄音"` 字串插值 | 改 `Text("clips_counter \(N) \(M)")` → xcstrings 格式字串 |
| VoiceLibraryView 上限按鈕 | 同上插值問題 | 改 `Text("clips_limit_reached \(N)")` |
| RingtonePickerSheet | `Text(emoji + " " + name)` 字串拼接 | 改 `Text(emoji) + Text(LocalizedStringKey(name))` |
| AlarmEditorView | `ringtoneDisplayName: String` | 改 `ringtoneDisplayKey: LocalizedStringKey` |

---

## 六、需要手動加進 Xcode Target 的新檔案

> 用 Xcode Project Navigator 右鍵 → Add Files to "SunnyWalker"，確認勾選 SunnyWalker target。

- `SunnyWalker/Views/Settings/VoiceLibraryView.swift`
- `SunnyWalker/Views/Settings/RingtonePickerSheet.swift`
- `SunnyWalker/Views/Components/GiraffeAvatar.swift`
- `SunnyWalker/Views/Components/MascotView.swift`

---

## 七、下次開工前 Checklist

- [ ] 四個新檔案加入 Xcode target，確認 build pass
- [ ] 真機測試錄音管理（錄 → 試聽 → 刪除）
- [ ] 真機測試鈴聲選擇（內建 + 自錄）
- [ ] 真機測試長頸鹿主題切換
- [ ] 英文模式下逐頁確認沒有殘存中文 UI
- [ ] 補 Info.plist NSMicrophoneUsageDescription 的英文版（InfoPlist.xcstrings）
- [ ] AlarmKit entitlement uncomment + rebuild
- [ ] 準備 App Store 截圖（iPhone 6.9" 必填）+ 隱私政策 URL
