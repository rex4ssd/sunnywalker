
**1. AlarmKit — 不需申請、不需 entitlement** ✅

AlarmKit **不需向 Apple 申請任何 entitlement / capability**。只靠 `Info.plist` 的
`NSAlarmKitUsageDescription` ＋ runtime `AlarmManager.requestAuthorization()` 即可，
Developer Portal 沒有對應的申請項。`SunnyWalker.entitlements` 刻意留空、不設
`CODE_SIGN_ENTITLEMENTS`。送審不需為 AlarmKit 做任何後台操作。
（背景與驗證細節見 `docs/alarmkit_entitlement_and_submit.md`。）

---

**2. 繁體中文本地化**

App Store Connect → 你的 App → 版本頁面 → 左欄語言下拉選「Chinese, Traditional」→ 點「+」新增。

需填：
- **App 名稱**：`SunnyWalker`（或中文名）
- **副標題**（選填）：例如「吉卜力風格兒童鬧鐘」
- **描述**：完整 app 介紹（繁中版）
- **宣傳文字**（選填）：100 字以內，隨時可改不需重新審核
- **關鍵字**：鬧鐘、兒童、吉卜力等，逗號分隔，總長 ≤ 100 字元

---

**3. App Encryption Documentation**
你的 `Info.plist` 已設 `ITSAppUsesNonExemptEncryption = false`，代表不使用受出口管制的加密。
上傳 build 時 Xcode Organizer 會問一次，選「**No**」即可。App Store Connect 的 Encryption 欄位會自動標為豁免，不需另外上傳文件。

---

**4. App Privacy「Get Started」**

App Store Connect → App → App Privacy → Get Started。
針對 SunnyWalker，依實際情況填：
| 資料類型 | 是否收集 | 說明 |
|---|---|---|
| Name / Contact Info | 否 | |
| Health & Fitness | 否 | |
| Location | 否（除非用到） | |
| Audio Data | **是**（若錄音） | 用於語音喚醒功能，Not linked to identity |
| Identifiers | 否 | |
| Diagnostics | 否（若無 crash reporting） | |

選完後每個「是」的資料類型要回答：用途（App Functionality）、是否連結到用戶身份、是否用於追蹤。

# SunnyWalker 音訊
Audio Data → Yes, we collect audio data
用途：App Functionality
Linked to identity：No（Not linked to you）
Used for tracking：No