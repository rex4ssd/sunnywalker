# AlarmKit 授權說明

> 適用版本：iOS 26+  
> 更新日期：2026-06-03

---

## 什麼是 AlarmKit

AlarmKit 是 Apple 在 iOS 26（WWDC 2025）推出的系統級鬧鐘 API。  
在此之前，完整的鬧鐘功能（穿透靜音、全螢幕叫醒）只有 Apple 內建的「時鐘」app 才能使用。  
iOS 26 之後，第三方 app 可以申請相同權限，讓鬧鐘體驗跟系統時鐘完全一樣。

---

## 支援的 iOS 版本與裝置

### 最低要求

| 項目 | 需求 |
|------|------|
| iOS 版本 | **iOS 26.0 以上** |
| 最低晶片 | A13 Bionic |
| 最低機型 | **iPhone 11** |

### 支援機型列表

| 系列 | 機型 | 備註 |
|------|------|------|
| iPhone 11 系列 | iPhone 11, 11 Pro, 11 Pro Max | 最低支援機型 |
| iPhone 12 系列 | iPhone 12, 12 mini, 12 Pro, 12 Pro Max | |
| iPhone 13 系列 | iPhone 13, 13 mini, 13 Pro, 13 Pro Max | |
| iPhone 14 系列 | iPhone 14, 14 Plus, 14 Pro, 14 Pro Max | |
| iPhone 15 系列 | iPhone 15, 15 Plus, 15 Pro, 15 Pro Max | |
| iPhone 16 系列 | iPhone 16, 16 Plus, 16 Pro, 16 Pro Max | |
| iPhone 17 系列 | iPhone 17, 17 Air, 17 Pro, 17 Pro Max | |
| iPhone SE | SE 第 2 代（2020）、SE 第 3 代（2022）、SE 第 4 代（2024） | |

### 不支援 iOS 26 的機型（無法使用 AlarmKit）

| 機型 | 原因 |
|------|------|
| iPhone XS / XS Max | iOS 26 最後支援 iOS 18 |
| iPhone XR | iOS 26 最後支援 iOS 18 |
| iPhone X 及更早 | 同上 |

---

## AlarmKit 不需要 Entitlement，也不需向 Apple 申請

> ⚠️ 更正（以本帳號 Developer Portal 實測為準）：早期筆記曾說「要向 Apple 申請
> `com.apple.developer.alarms` entitlement」，**不正確**。

AlarmKit **不需要任何 entitlement、也沒有可申請的 capability**。啟用條件只有兩個：

1. `Info.plist` 的 `NSAlarmKitUsageDescription`（已有）。
2. runtime 呼叫 `AlarmManager.requestAuthorization()`，使用者按同意。

Developer Portal 的 **Capabilities / App Services / Capability Requests** 三處都查不到
AlarmKit / Alarms 項目——它不是 managed capability，沒有需求單可填、不用等核准。
`com.apple.developer.alarmkit` 也**不是**可 provision 的 entitlement，硬放進
entitlements 檔會讓自動簽章失敗（`Entitlement ... not found and could not be included
in profile`）。所以 `SunnyWalker.entitlements` 刻意留空、不設 `CODE_SIGN_ENTITLEMENTS`。

> **Simulator**：技術上可觸發 AlarmKit alert，但**沒有聲音**（系統限制）；響鈴一定要看實機。

---

## 有 AlarmKit 授權 vs 沒有授權的差異

### 有 AlarmKit 授權

用戶在 **設定 → SunnyWalker → 鬧鐘（Alarms）** 開啟後生效。

**鬧鐘觸發時的行為：**

| 功能 | 說明 |
|------|------|
| 顯示方式 | **全螢幕叫醒畫面**（跟 Apple 時鐘 app 相同） |
| 靜音模式 | ✅ **穿透靜音**，一定會響 |
| 勿擾模式 / Focus | ✅ **穿透所有 Focus**，一定會響 |
| 鎖定畫面 | ✅ 直接顯示全螢幕 alert |
| Dynamic Island | ✅ 鬧鐘倒計時顯示在 Dynamic Island |
| Apple Watch | ✅ 同步叫醒 Apple Watch |
| 鬧鐘數量 | **無限制** |
| 重複設定 | ✅ 每週特定幾天重複，無限制 |
| 重開機後 | ✅ 鬧鐘由系統管理，不受 app 重啟影響 |
| App 更新後 | ✅ 不會失效 |
| 自訂聲音 | ✅ 可用 `.named("sunny_wake.caf")` 指定 bundle 內的音效 |
| 停止按鈕 | ✅ 全螢幕有「我起床了」停止 / 貪睡按鈕 |

**SunnyWalker 的流程（有授權）：**
```
鬧鐘時間到
→ AlarmKit 系統全螢幕叫醒畫面
→ 用戶點「我起床了」
→ StopAlarmIntent 執行
→ app 開到前景
→ AlarmRingView 顯示（龍貓搖晃 + 播放錄音）
→ 說出起床咒語 / 按按鈕
→ RewardView（獎勵畫面）
```

---

### 沒有 AlarmKit 授權（Fallback：UNNotification）

發生情況：用戶**拒絕**授權、裝置不支援 iOS 26、或 entitlement 尚未批准。

**鬧鐘觸發時的行為：**

| 功能 | 說明 |
|------|------|
| 顯示方式 | **普通通知橫幅**（頂部小 banner） |
| 靜音模式 | ❌ **會被靜音**，可能沒聲音 |
| 勿擾模式 / Focus | ❌ **可能被 Focus 擋掉** |
| 鎖定畫面 | 普通通知樣式，不是全螢幕 |
| Dynamic Island | ❌ 不支援 |
| Apple Watch | ❌ 不同步 |
| 鬧鐘數量 | 受系統通知限制 |
| 重開機後 | ⚠️ 可能失效（iOS UNNotification 限制） |
| App 更新後 | ⚠️ 可能需要重新排程 |
| 聲音 | `.default` 系統通知音（保證有聲但不是自訂音效） |

**SunnyWalker 的流程（沒有授權）：**
```
鬧鐘時間到
→ UNNotification 通知橫幅（系統通知聲）
→ 用戶點通知
→ app 開到前景
→ AlarmRingView 顯示
→ 說出起床咒語 / 按按鈕
→ RewardView
```

---

## 對比總結

| 能力 | AlarmKit（有授權）| UNNotification（沒授權）|
|------|:---:|:---:|
| 穿透靜音 | ✅ | ❌ |
| 穿透 Focus | ✅ | ❌ |
| 全螢幕叫醒 | ✅ | ❌ |
| Dynamic Island | ✅ | ❌ |
| Apple Watch 同步 | ✅ | ❌ |
| 重開機後仍有效 | ✅ | ⚠️ |
| 自訂聲音 | ✅ | ⚠️（受格式限制）|
| 無限鬧鐘數量 | ✅ | ⚠️ |
| iOS 最低版本 | iOS 26 | iOS 10+ |
| 需要特殊 entitlement | ✅ 需要 Apple 審核 | ❌ 不需要 |

---

## SunnyWalker 的實作策略

```
app 啟動
├── 申請 AlarmKit 授權
│   ├── 授權成功 → 走 AlarmKit 路徑（AlarmKitService）
│   │   └── sound: .named("sunny_wake.caf")  [真機]
│   │       （Simulator 跳過 sound，避免 ToneLibrary crash）
│   └── 授權失敗 / 拒絕 → 走 UNNotification 路徑（AlarmScheduler）
│       └── content.sound = .default
│
└── 兩條路都能開啟 AlarmRingView → 播放錄音 + 語音辨識
```

> **重要**：如果 AlarmKit 排程失敗，UNNotification fallback 會保留作備用。  
> 只有確認 AlarmKit 成功排程後，才會取消對應的 UNNotification。

---

## 參考資料

- [AlarmKit — Apple Developer Documentation](https://developer.apple.com/documentation/AlarmKit)
- [iOS 26 Makes Third-Party Alarm and Timer Apps Better — MacRumors](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)
- [iPhone models compatible with iOS 26 — Apple Support](https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/ios)
- [iOS 26 Supported Devices — EveryMac](https://everymac.com/systems/apple/iphone/iphone-faq/iphone-ios-26-supported-devices-features.html)
