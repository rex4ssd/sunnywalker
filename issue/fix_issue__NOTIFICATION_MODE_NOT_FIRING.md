# fix：提醒模式（Time-Sensitive 通知）完全沒反應 → 已解 + 後續優化

> 日期：2026-06-12
> 狀態：🟢 **已解，真機驗證成功**（鎖屏出現 TIME SENSITIVE 橫幅 + 自訂錄音聲）
> 對應 issue：`issue/NOTIFICATION_MODE_NOT_FIRING.md`（原始除錯交接文件，§9 有完整排查鏈）

---

## 發生什麼事（一句話）

`project.yml` 加了 `CODE_SIGN_ENTITLEMENTS` 但**沒跑 `xcodegen generate`**，time-sensitive entitlement 從沒進過 binary；iOS 對「標了 `.timeSensitive` 卻沒有 entitlement」的通知是**整顆悄悄丟棄**——不顯示、不出聲、不進 delivered 清單。

---

## 1. 根因鏈

```
project.yml 加 CODE_SIGN_ENTITLEMENTS（§2-B.7）
  → 沒跑 xcodegen generate
  → project.pbxproj 裡 grep 不到 CODE_SIGN_ENTITLEMENTS（決定性證據）
  → entitlement 沒進 binary
  → content.interruptionLevel = .timeSensitive 的通知被 iOS 整顆丟棄
  → pending=7（排程正常）但 delivered=0、到點無橫幅無聲音
```

### 排查過程（如何收斂到這裡）

| 步驟 | 結果 |
|------|------|
| log 時間線顯示 11:50 已過才在 12:09 測 → 疑似假設 D | 使用者確認測試時有改成未來時間 → **D 排除** |
| 設定截圖顯示 Notifications: Banners, Sounds, Badges | 授權正常 → **假設 A 排除** |
| 確認無 Apple Watch（鎖屏通知會被路由到 Watch） | **Watch 路由排除** |
| 設定 ▸ SunnyWalker ▸ Notifications 內頁**沒有「Time Sensitive」開關** | 開關不存在＝entitlement 不在 binary ← **決定性線索** |
| `grep CODE_SIGN_ENTITLEMENTS SunnyWalker.xcodeproj/project.pbxproj` → 無結果 | **根因定案** |

### 重要知識修正（原文件假設 C 的錯誤前提）

原文件以為「entitlement 缺失只會降級成一般通知、仍會顯示」→ **錯**。
實測：entitlement 缺失 + `.timeSensitive` ＝ **通知整顆被丟**（連 delivered 清單都不進）。
這也解釋了不對稱：AlarmKit 不走 UNNotification 路徑所以會響。

---

## 2. 修了什麼

### 2-A. 根因修復
1. **跑 `xcodegen generate`**，確認 pbxproj 含 `CODE_SIGN_ENTITLEMENTS`。
2. **runtime 防衛**（`AlarmScheduler.swift`）：讀 `notificationSettings().timeSensitiveSetting`，
   `!= .enabled`（0=notSupported=entitlement 缺、1=使用者關閉）時降回 `.active` 並印警告
   → 以後 entitlement 再掉，通知至少正常顯示，不會無聲失敗。
3. 診斷 log 加印 `timeSensitive=` 欄位（`🚦 AlarmScheduler: UN authStatus=… timeSensitive=…`）。

### 2-B. 「只響 3 秒就停」修復
- 原因：通知音效**只播一次、長度＝CAF 檔長**（上限 30s）。錄音 3 秒 → 只響 3 秒。
- **`AudioRecorder.swift`（AlarmSoundExporter）**：匯出時把錄音 **loop 填滿 ~29 秒**
  （留 margin，>30s 會被 iOS 整顆 fallback 成預設音）→ 單響拉滿 30 秒。
- **`AlarmScheduler.swift` 自我修復**：排程時偵測既有 CAF <28s → 用原錄音自動重匯出 loop 版，
  免重錄（log：`short CAF (3.0s) re-exported as 29s loop`）。
- AlarmKit 模式不受影響（系統對 alarm sound 本來就無限循環，長 CAF 兩種模式都安全）。

### 2-C. UX 優化（真機驗證成功後）
1. **橫幅文案**：body 原本顯示「點開來聽：`<recordingName>`」，但 recordingName 是內部 UUID，
   鎖屏出現一串亂碼（實機截圖證實）。改成顯示 **`alarm.label`**（專注提醒要做的事），
   沒 label 用通用早安語。
2. **點擊行為**：提醒模式聲音播完已自動停，沒有「關鬧鐘」需求 → 點橫幅**只回主畫面**，
   不再開 AlarmRingView（「我起床了！」喚醒畫面）。
   - 作法：`userInfo` 加 `"backgroundMode"`，`AppDelegate.didReceive` 的 tap 分支對
     `.notification` 跳過 `handleAlarmPayload`。
   - AlarmKit / 舊 fallback 路徑維持原行為。
   - ⚠️ 改版前排的舊通知 userInfo 沒有這個 key → 點了仍開喚醒畫面；開一次 app
     讓前景補排程重排（`schedule()` 會 remove stale + re-add）即恢復正常。

---

## 3. 通用教訓

1. **改 `project.yml` 的任何 build setting 後必跑 `xcodegen generate`**，並 grep pbxproj 確認 key 真的進去。
2. **「設定 ▸ app ▸ 通知」內頁有沒有「Time Sensitive」開關**＝entitlement 是否在 binary 的免工具檢查法；
   程式內用 `timeSensitiveSetting == .notSupported` 偵測。
3. 通知音效要響滿 30 秒，CAF 要自己 loop 填滿（系統不會幫你重複播）。
4. 以上均已寫入 Vein（pitfall `20260612-125817-3b9e`、`20260612-130711-0425`）。

## 4. 改動檔案

- `SunnyWalker/Services/AlarmScheduler.swift` — timeSensitive 防衛 + 診斷 log + 短 CAF 自我修復 + body 改 label + userInfo 加 backgroundMode
- `SunnyWalker/Services/AudioRecorder.swift` — exporter loop 填滿 ~29s
- `SunnyWalker/SunnyWalkerApp.swift` — didReceive tap 分流（提醒模式不開 ring view）
- `SunnyWalker.xcodeproj/project.pbxproj` — `xcodegen generate` 後含 CODE_SIGN_ENTITLEMENTS
