# SunnyWalker — Apple 識別碼總表 / Identifiers

> 所有上架要用的 ID 集中在這裡。**註冊後不可更改**的標 🔒。
> 修改 App 設定（bundle id / entitlement）前先看這份。
> 參照：`lode_iphone/docs/for_Apple_store/IDENTIFIERS.md`

---

## 1. 開發者帳號 / Team

| 項目 | 值 |
|---|---|
| Apple Developer 帳號 | RUEI YI WU |
| Team ID 🔒 | `NHY8MKW8NH` |
| 角色 | Admin |
| 設定來源 | `project.pbxproj` → `DEVELOPMENT_TEAM` |

---

## 2. App 識別碼 / Bundle IDs

| 用途 | Bundle ID | 備註 |
|---|---|---|
| **主 App（App Store 版）** 🔒 | `app.rexcode.sunnywalker` | App Store Connect 註冊後不可改 |
| 測試 target | `app.rexcode.sunnywalkertests` | 不上架 |

- 桌面顯示名稱（home screen）：`SunnyWalker`（`Info.plist` → `CFBundleDisplayName`）
- App Store 顯示名稱：見 `APP_STORE_LISTING.md`（與顯示名稱可不同）

---

## 3. iCloud 容器

SunnyWalker **不使用 iCloud**。家長錄音與所有資料存放在裝置本機 `Documents/Recordings/`，不需申請 iCloud container。

---

## 4. App Store Connect

| 欄位 | 值 |
|---|---|
| SKU（內部識別，不可空） | `sunnywalker-ios-001` |
| 主要語言 | English (en) |
| 額外語言 | 繁體中文（zh-Hant） |
| 平台 | iOS（iPhone + iPad，`TARGETED_DEVICE_FAMILY = 1,2`） |
| 最低系統 | iOS 26.0 |
| 版本 / build | `1.0.20260610` / `4`（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；Info.plist 用 `$(...)` 引用。與 Lode 一致：marketing=MAJOR.MINOR.YYYYMMDD、build=遞增整數。每次 re-upload 更新日期段與 build int）|
| 主類別 | Education |
| 次類別 | Utilities |
| 年齡分級 | 4+ |
| 出口加密 | `ITSAppUsesNonExemptEncryption = false`（已設於 Info.plist） |

---

## 5. 支援 / 隱私 URL（送審必填）

| 欄位 | URL | 狀態 |
|---|---|---|
| Support URL | `https://rexcode.app/sunny_walker/support/` | ✅ 已建立 |
| Privacy Policy URL | `https://rexcode.app/sunny_walker/privacy/` | ✅ 已建立 |
| Marketing URL（選填） | `https://rexcode.app/sunny_walker/` | ✅ 已建立 |

---

## 6. Entitlements

| Key | 值 | 狀態 |
|---|---|---|
| （無）| — | ✅ **不需任何 entitlement** |

**AlarmKit 不需要 entitlement，也不需向 Apple 申請。** 只靠 `Info.plist` 的
`NSAlarmKitUsageDescription` ＋ runtime `AlarmManager.requestAuthorization()` 即可。
`com.apple.developer.alarmkit` 不是 Developer Portal 可勾選 / 可申請的 managed capability
（Capabilities / App Services / Capability Requests 三處皆查無），硬塞進 entitlements 檔
反而會讓自動簽章失敗（`Entitlement com.apple.developer.alarmkit not found...`）。
因此 `SunnyWalker.entitlements` 刻意保持空白、也不設 `CODE_SIGN_ENTITLEMENTS`。
詳見 `docs/alarmkit_entitlement_and_submit.md`。

---

## 7. 雙軌金流識別碼（未來 Pro，先定命名規則）

> 完整架構與合規見 `docs/Paymen_mechanism.md`。
> 目前 v1.0 免費上架，以下為日後新增 IAP 時的命名備忘。

### App Store IAP Product IDs（建議命名）

| 產品 | Product ID | 類型 |
|---|---|---|
| SunnyWalker Pro（終身） | `app.rexcode.sunnywalker.pro.lifetime` | Non-Consumable |
| SunnyWalker Pro（年訂閱） | `app.rexcode.sunnywalker.pro.yearly` | Auto-Renewable |
| SunnyWalker Pro（月訂閱） | `app.rexcode.sunnywalker.pro.monthly` | Auto-Renewable |

### Lemon Squeezy（直售授權碼）

| 項目 | 值 |
|---|---|
| Store / Product ID | （待建立後填） |
| License API | `https://api.lemonsqueezy.com/v1/licenses/*` |
| 說明 | 使用者在官網購買後，於 App 內「輸入授權碼」兌換 Pro，不違反 Apple 3.1.3 |

---

## 8. 目前未使用（備忘）

- **iCloud / CloudKit**：未使用（錄音存本機）
- **App Group**：未使用（無 extension / widget）
- **Push Notifications**：未使用（AlarmKit 取代通知鬧鐘路徑）
- **Sign in with Apple**：未使用（無帳號系統）
- **URL Scheme**：未使用
