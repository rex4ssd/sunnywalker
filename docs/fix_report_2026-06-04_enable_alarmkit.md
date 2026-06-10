# SunnyWalker — 啟用 AlarmKit + 修好鎖屏/前景響鈴（2026-06-04）

> 🔴 **2026-06-10 更正：** AlarmKit **不需 entitlement、也不需向 Apple 申請**。本文中任何「申請 / 等批准 / portal 開啟 Alarms capability / 解除 entitlements 註解」的敘述已**不適用**；現行 repo 的 `SunnyWalker.entitlements` 留空、不設 `CODE_SIGN_ENTITLEMENTS`。最新結論見 `docs/alarmkit_entitlement_and_submit.md`。


**狀態：** ✅ 鎖屏響鈴、前景響鈴、前景聲控停鬧鐘、麥克風只在響鈴時開 —— 全部真機驗證通過，準備上 App Store。

> 這份是 2026-06-04 的權威現況報告。它**修正/取代** `fix_report_2026-06-03_three_alarm_bugs.md` 與 `design_background_voice_stop.md` 裡「AlarmKit 還沒批、UN 是 fallback、背景聆聽常駐」等假設——那些是昨天 AlarmKit 未生效時的狀態，今天已不同。

---

## 一句話總結

關屏不響的真正原因**不是程式邏輯**，而是**組態**：AlarmKit 從頭到尾沒被簽進 binary，所以一直默默退回普通 UN 通知（靜音/鎖屏本來就不會像鬧鐘響）。把 AlarmKit 正確啟用後，鎖屏/靜音響鈴就成立；其餘是前景響鈴的幾個音訊 session 細節。

---

## 排查時走過的彎路（先記下來，避免再被誤導）

1. **誤判一：怪 commit `05e7975` 的 `guard !isAuthorized` stand-down。** 錯。因為當時 `isAuthorized` 根本是 `false`（AlarmKit 沒生效），那條 guard 反而是放行的，UN 一直有排。
2. **誤判二：怪 active 的 `.playAndRecord` session 把通知音 duck 掉。** 部分相關但不是主因——log 顯示 `prevCategory=SoloAmbient`（等於沒有錄音 session）時關屏一樣不響。
3. **真因（log 一翻兩瞪眼）：** `AlarmKitService: requestAuthorization failed … Code=1` + `AlarmKitAuthorized=false`。AlarmKit 沒授權 → 全程走 UN → 普通通知無法穿透靜音/鎖屏。

教訓：**先看 log 把「現在到底走哪條路徑」確定下來，再談邏輯。** `AlarmKitAuthorized=` 那行就是路徑開關。

---

## 根因與修法

### A. AlarmKit 授權吃 `Code=1`（關屏不響的根） — 組態問題

**根因：** `SunnyWalker.entitlements` 只被列進 Xcode 專案（PBXFileReference，出現在 project navigator），但**沒有任何 `CODE_SIGN_ENTITLEMENTS` build setting 指向它**；而 XcodeGen 的權威來源 `project.yml`（`xcodegen generate` 會重產 pbxproj/Info.plist）的 target 也完全沒宣告 entitlements。再加上 `NSAlarmKitUsageDescription` 被從 Info.plist 移除（iOS 26 的 `requestAuthorization()` 需要它）。三者合起來 → `com.apple.developer.alarmkit` 從未簽進 binary → 授權 throw `Error Domain=com.apple.AlarmKit.Alarm Code=1` → `isAuthorized=false` → 靜默退回 UN。

**修法：**
- `SunnyWalker.entitlements`：解除 `com.apple.developer.alarmkit` 的 XML 註解。
- `project.yml` → target `settings.base` 加 `CODE_SIGN_ENTITLEMENTS: SunnyWalker/SunnyWalker.entitlements`（直接設 build setting，不用 XcodeGen `entitlements.properties` 以免它重產覆蓋手寫檔）。
- `Info.plist` + `project.yml` `info.properties` 還原 `NSAlarmKitUsageDescription`。
- 之後必須 `xcodegen generate` 才會把設定寫進 pbxproj。

**🔴 踩雷教訓：在 XcodeGen 專案，「entitlements 檔存在 / 在 navigator」≠「有簽進 binary」。** 一定要在 `project.yml` 設 `CODE_SIGN_ENTITLEMENTS`（或 target 的 `entitlements:`）。光把 .entitlements 拖進 Xcode、或留一個註解好的檔，都不會生效，而且失敗是**靜默退回 fallback**，不會 build error，最難查。

**使用者端（非程式）：** developer.apple.com 的 App ID `app.rexcode.sunnywalker` 要開啟 AlarmKit capability、provisioning profile 要含此 entitlement，否則簽章/授權仍會失敗。

---

### B. UN 通知不是真鬧鐘（平台限制，寫下來免得再期待）

普通 `UNNotification`：在**靜音/鈴聲開關關閉/專注模式**下只顯示橫幅、不出聲；且通知音上限約 30 秒。能像系統時鐘那樣「鎖屏＋靜音照響、連續響」的只有 **AlarmKit** 或 **Critical Alerts entitlement**。所以「不要背景常駐錄音」+「靜音也要響」這兩個需求**只能靠 AlarmKit**，沒有第三條合規路徑。診斷時可看 `🔔 NotifSettings:` 那行的 `sound=` / `timeSensitive=`。

---

### C. 前景開鬧鐘畫面卻無聲 — `AlarmRingView.startAudio` 漏看 Library/Sounds

**根因：** 自訂鈴的 CAF 由 `AlarmSoundExporter` 寫在 **`Library/Sounds/`**（給通知用），但 `startAudio` 只找 `Documents/Recordings/*.m4a` 和 **app bundle**，兩邊都沒有 → 落到 `skipping playback` → 整個起床畫面無聲。

**修法：** `startAudio` 改成依序找並**絕不 skip**：① 家長錄音 m4a → ② alarm `soundFileName` 的 CAF（**Library/Sounds**）→ ③ 同名 bundle 檔 → ④ 保底 bundled `sunny_wake.caf`。loop 間隔用 `recordingGapSeconds`（預設 2s），聽寫時 duck 到 0.12 → 自動「小聲＋間隔」，不影響辨識。

**🟡 教訓：** 自訂音檔散在三個位置（Documents/Recordings 的 m4a、Library/Sounds 的 caf、bundle 的預設），任何「找鬧鈴」邏輯都要三處都查 + 一個永遠存在的保底，不能讓響鈴畫面有任何無聲的分支。

---

### D. 前景響鈴「響 0.5 秒就斷」 — audio session 啟用競態

**根因：** `HomeView.checkForegroundAlarm` 先 `AlarmKitService.stop(id:)`（非同步）再立刻開 `AlarmRingView` → `AudioPlayer.play` 馬上 `setActive(.playback)`。AlarmKit **非同步**釋放它的 session，第一次啟用輸給競態 → throw `Session activation failed`（status `560557684`，即 priority 不足/無法插斷）→ 響鈴瞬間沒聲。約 1 秒後 `.playAndRecord` 反而成功，證明只是時序。

**修法：** `AudioPlayer.play` 改成 `activateSessionAndStart(attempt:)`，啟用失敗就每 0.3s 重試、最多 8 次（用 `Task { @MainActor }` 避免 actor 隔離編譯錯），AlarmKit 一放手就接手；用 `currentURL == url` 防止被新的 play/stop 蓋過。session 仍只在 play() 設定一次（loop 重播不碰 session，保住 SpeechRecognizer 後續切 `.playAndRecord`）。

**🟡 教訓：** 任何「停掉別人的 audio（尤其 AlarmKit）後馬上自己 setActive」都要假設對方**非同步釋放**，啟用要能重試，否則就是這種「響一下就沒」的鬼。

---

### E. 麥克風橘點一直亮 — BGListen cold-launch 常駐

**根因：** cold launch 時授權還沒回來（`isAuthorized=false`），`HomeView` 就啟動了常駐麥克風 `BackgroundListeningManager`（橘點亮）；之後 AlarmKit 授權了也沒人去關它。

**修法：** ①`AlarmKitService.requestAuthorization()` 一旦 `isAuthorized=true` 立刻 `BackgroundListeningManager.shared.stop()`（關掉 cold-launch 那一隻）；②`HomeView.syncBackgroundListening()` 的啟動條件加 `&& !AlarmKitService.shared.isAuthorized`。

**結果（符合需求）：** AlarmKit 當道時**永不**啟動常駐麥克風；麥克風只在 `AlarmRingView` 響鈴期間（前景聲控停鬧鐘）才開，響完即關。

---

### F. 進背景釋放 audio session

`HomeView` 的 `scenePhase` 進背景/鎖屏時 `stop()` BGListen + `AVAudioSession.setActive(false, .notifyOthersOnDeactivation)`（涵蓋前景聲控可能留下的 SpeechRecognizer/AudioPlayer session），但 **`firingAlarm != nil`（前景 AlarmRingView 正在響）時不關**，以免切斷正在響的鈴。兼顧省電/不長亮橘點與不誤殺響鈴。

---

## 最終狀態（AlarmKit shipping config）

| 情境 | 行為 |
|------|------|
| 鎖屏 / 靜音 | AlarmKit 全螢幕鬧鐘響（非 strict → `DismissAlarmIntent`，✕ 直接關） |
| App 前景沒關屏 | `checkForegroundAlarm` 停 AlarmKit、改開 `AlarmRingView` 自己響（自訂鈴 loop + gap），說「我起床了」可停 |
| 麥克風 | 只在 `AlarmRingView` 響鈴期間開；其餘時間關（無橘點長亮） |
| AlarmKit 未授權（退路） | 退回 UN 通知 + （若開啟實驗開關）BGListen，但這不是 shipping 預期狀態 |

---

## 改動檔案（本輪 2026-06-04）

| 檔案 | 改動 |
|------|------|
| `SunnyWalker.entitlements` | 解除 `com.apple.developer.alarmkit` 註解 |
| `project.yml` | 加 `CODE_SIGN_ENTITLEMENTS` + `NSAlarmKitUsageDescription` |
| `Info.plist` | 還原 `NSAlarmKitUsageDescription` |
| `Services/AlarmKitService.swift` | 授權成功即停 BGListen |
| `Services/AudioPlayer.swift` | session 啟用失敗重試（修「響 0.5 秒斷」） |
| `Views/Alarm/AlarmRingView.swift` | `startAudio` 查 Library/Sounds + 保底，永不無聲 |
| `Views/Home/HomeView.swift` | 進背景釋放 session（響鈴中除外）+ 授權時不啟動 BGListen + `import AVFoundation` |
| `Services/PermissionManager.swift` | dump `🔔 NotifSettings:` 診斷 |

---

## 🚦 上 App Store 前的待辦 / 風險（請先看）

1. **`UIBackgroundModes: audio` 建議移除（2.5.4 退件風險）。** shipping 走 AlarmKit 時，背景**完全沒有**音訊播放/錄音（BGListen 已停用、聲控只在前景）。宣告了 `audio` 背景模式卻沒在背景用，Apple 會質疑。移除它不影響 AlarmKit 鬧鐘與前景聲控；只會讓「AlarmKit 未授權時的 BGListen 退路」無法在背景保活——但那不是 shipping 狀態。**待你決定是否移除。**
2. **診斷 `print()`／`🔔 NotifSettings` log** 留著不影響審核，但 release 可考慮關掉或包 `#if DEBUG`（可另開一輪）。
3. **AlarmKit entitlement 必須在 App ID / provisioning profile 真的開啟**，否則 TestFlight/正式簽章會失敗。
4. 既有編譯 warning（`UIScreen.main` deprecated、Localization actor-isolated 等）未處理，不阻擋 build。
5. App Store 圖片/截圖一律 **RGB 無 alpha**（舊雷，已知）。

---

## Vein 已記錄

本輪根因與決策已寫回 Vein（`project:sunnywalker`）：AlarmKit Code=1 組態根因、scenePhase/duck 誤判更正、AlarmRingView Library/Sounds、AudioPlayer 啟用競態、BGListen cold-launch 常駐。
