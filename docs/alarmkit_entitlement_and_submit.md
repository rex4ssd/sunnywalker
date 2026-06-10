# AlarmKit entitlement + App Store 送審筆記（2026-06-04）

> 🔴 **2026-06-10 更正（以現行 repo 為準）：** 本文部分內容停在 06-04 的中間狀態。
> **最終決定：AlarmKit 不需要 entitlement、也不需向 Apple 申請。**
> `SunnyWalker.entitlements` 現在**刻意留空**、`project.yml` 也**不設 `CODE_SIGN_ENTITLEMENTS`**
> （把 `com.apple.developer.alarmkit` 放進去會讓自動簽章失敗）。啟用只靠 `Info.plist` 的
> `NSAlarmKitUsageDescription` ＋ runtime `AlarmManager.requestAuthorization()`。
> ⚠️ **待驗證**：本文曾把「`requestAuthorization()` 從 `Code=1` 變 authorized」歸因於補上
> entitlement；但現行 repo 已移除該 entitlement，需在真機重新確認授權仍成功。

## ✅ 已完成（程式端，已 commit）

- 鎖屏 / 靜音響鈴：AlarmKit 全螢幕鬧鐘（已啟用、真機驗證）。
- 前景響鈴 + 聲控停鬧鐘：`AlarmRingView` 自訂鈴 loop（修好 Library/Sounds 查找 + session 啟用重試）。
- 麥克風只在響鈴時開（AlarmKit 授權後關閉常駐 BGListen，無橘點長亮）。
- AlarmKit 授權路徑：`NSAlarmKitUsageDescription` + runtime `requestAuthorization()`（**無** entitlement、**無** `CODE_SIGN_ENTITLEMENTS`；見頂部更正）。
- 最低 iOS 版本：`IPHONEOS_DEPLOYMENT_TARGET = 26.0`（project.yml 與 pbxproj 一致）。

## 🔜 接下來要做（送審待辦，依序）

1. **🔴 Xcode → Product → Archive →（自動簽章）→ Distribute → TestFlight。** 上傳沒跳「profile 不含 com.apple.developer.alarmkit」就代表發佈簽章有帶上 AlarmKit。
2. **🔴 用「第二支非開發機」裝 TestFlight 版測鎖屏響鈴**（iPhone）。這是「別人也能用」的唯一可靠證明。過了才送正式審。
3. **🟡 iPad 10（實體，MPQ13TA/A，需 iPadOS 26+）測響鈴**；iPad 10 模擬器（iOS 26.5）測版面。Simulator 只驗版面，AlarmKit 響鈴一定看實機。
4. **🟡 AlarmKit 在第二機/iPad 確認 OK 後 → 移除 `UIBackgroundModes: audio`**（project.yml + Info.plist），避免 App Store 2.5.4 退件（shipping 走 AlarmKit 時背景沒用到音訊）。← 這步叫 Claude 幫改。
5. **🟢 可選**：把診斷 `print()` 包 `#if DEBUG`；App Store 截圖一律 RGB 無 alpha；兒童 App 隱私說明（錄音/語音 on-device 不外傳）。

### 最低 iOS 版本：不用在 Apple 後台填
最低版本由 build 的 `IPHONEOS_DEPLOYMENT_TARGET = 26.0` 決定，**自動同步**到 App Store Connect 與商店頁「需要 iOS 26.0 或以上」。後台**沒有**手動欄位。iOS 26 以下使用者會被擋在下載前（不是「裝了壞掉」），iOS 26+ 使用者正常安裝、無警告。代價：受眾僅限已升級 iOS 26 的裝置（AlarmKit 的必要代價）。

---

## 重點結論：AlarmKit 不需要向 Apple 申請

在 Developer Portal 的 App ID（`app.rexcode.sunnywalker`，Team `NHY8MKW8NH`）三個分頁實測：

- **Capabilities** 搜 `AlarmKit` / `Alarms` → 空
- **App Services** → 無
- **Capability Requests** 搜 `AlarmKit` → 空

→ **AlarmKit 不是 portal 可勾選 / 可申請的 managed capability。沒有需求單可填、不用等核准。**
而且它**根本不需要 entitlement**：
1. `SunnyWalker/SunnyWalker.entitlements` **留空**（放 `com.apple.developer.alarmkit` 反而會讓自動簽章報 `Entitlement ... not found and could not be included in profile`）。
2. `project.yml` **不設** `CODE_SIGN_ENTITLEMENTS`。
3. 啟用只靠 `Info.plist` 的 `NSAlarmKitUsageDescription` ＋ runtime `AlarmManager.requestAuthorization()`，用**自動簽章**（`DEVELOPMENT_TEAM = NHY8MKW8NH`）build 即可。

> ⚠️ 本文舊版曾把「`requestAuthorization()` 由 `Code=1` 變 authorized」歸因於補 entitlement，
> 但現行 repo 已把 entitlement 移除（留空）。送審前請在真機重新確認授權仍回 `authorized`。

> 先前查到部落格說「要向 Apple 申請」是不準的；以這個帳號 portal 的實際畫面為準：沒有申請項。

## 「自己手機能跑，別人能不能跑」怎麼確定

開發機能跑 ≠ App Store 版能跑（開發簽章較寬鬆）。唯一可靠驗證 = **TestFlight + 第二支手機**：

1. Xcode → **Product → Archive**（自動簽章）。
2. **Distribute → TestFlight**。上傳若**沒有**跳「provisioning profile 不含 `com.apple.developer.alarmkit`」→ 發佈 profile 已正確含 AlarmKit。
3. 用**另一支非開發註冊**的 iPhone（iOS 26+）裝 TestFlight 版 → 跑鬧鐘 → 看 log `AlarmKitService: authorization → authorized` + 鎖屏會響。
4. 第二機 OK → 才送 App Store 正式審。

保持自動簽章；不要切手動（手動要自建含此 entitlement 的 profile，portal 無此選項，會卡）。

## 送審前 checklist

- [ ] TestFlight 第二支手機驗證 AlarmKit 鎖屏響鈴（上一節）。
- [ ] **`UIBackgroundModes: audio` 決定**：shipping 走 AlarmKit 時背景沒有任何音訊/錄音（BGListen 已停用、聲控只在前景）。宣告了卻沒用 → Apple Guideline **2.5.4** 退件風險。
      - 建議：確認 AlarmKit 在 TestFlight 第二機 OK 後，從 `project.yml` info.properties + `Info.plist` **移除** `UIBackgroundModes: audio`（不影響 AlarmKit 與前景聲控；只讓「AlarmKit 未授權時的 BGListen 背景保活」失效，而那不是 shipping 狀態）。
- [ ] 診斷 `print()`（`🔔`/`🎬`/`🔊`/`🎤`/`🟠` 及 `🔔 NotifSettings`）可考慮包 `#if DEBUG`，release 不輸出。
- [ ] App Store 圖片/截圖一律 **RGB 無 alpha**。
- [ ] 兒童 App：隱私說明要明確（錄音/語音 100% on-device、不外傳），對應 `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` 已有。
- [ ] 既有編譯 warning（`UIScreen.main` deprecated 等）不阻擋 build，可日後清。

## 申請表（萬一某天 Apple 真的改成要申請時備用）

若未來 portal 出現 AlarmKit 的 Capability Request，可貼這段英文 justification：

> **App name:** SunnyWalker — a children's wake-up alarm clock. A parent records their own voice (or picks a sound) and sets recurring weekday alarms; the child completes a short wake-up interaction (e.g. saying "I'm awake") to stop the alarm.
> **Why AlarmKit:** the core feature is a dependable morning alarm that must sound on the Lock Screen and break through Silent mode and Focus, exactly like the built-in Clock app — a standard local notification cannot. Used only for genuine user-set alarms (scheduling, Lock Screen / Dynamic Island stop-snooze UI, routing stop into the app), never for reminders, marketing, or background tasks.
