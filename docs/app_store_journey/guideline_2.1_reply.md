# Guideline 2.1 — Information Needed 回覆（2026-06-11）

> Submission ID: 36ba9a12-3079-4341-ad8b-66c64ae1bb5d
> Review device: iPad Air 11-inch (M3) ‧ Version reviewed: **1.0.20260610 (2)**
> 性質：不是硬退，是 Made for Kids 的標準資料提問。回覆即可繼續審。

## ⚠️ 重要：審的還是 build (2)

退件信的 `Version reviewed: 1.0.20260610 (2)` 仍是舊 binary，**沒有權限英文化修正**（`InfoPlist.xcstrings` 在 build 3 才加）。
回覆 2.1 後若審核員繼續用 build 2 測權限，上一輪的 **Guideline 4（中文權限框）**很可能再出現。
→ **建議把 build 換成 5（Version 顯示 1.0.20260610），再繼續。** 若狀態不允許換 build，就重開一筆 submission 選 build 5，並把下方答覆貼進 App Review notes。

---

## 回覆全文（英文，貼回 App Store Connect Resolution Center）

```
Thank you. SunnyWalker is a fully offline children's alarm clock and collects no data.

• Third-party analytics? No. The app contains no analytics SDKs of any kind
  (no Firebase, Crashlytics, Google Analytics, etc.).

• Third-party advertising? No. The app contains no ad SDKs and displays no advertising.

• Data shared with third parties? No. The app makes no network requests of its own
  and has no third-party partners. We (the developer) never receive any user data.

• Any user/device data collected beyond analytics/ads? No. Everything created in
  the app is stored on the device only and is never transmitted to us:
   – Alarm settings (time, label, task type) — stored locally.
   – Parent voice recordings — stored only in the app's local Documents folder.
   – Wake-up history (timestamps) — stored locally, shown only to the parent.
   – Microphone & Speech Recognition — used solely so the child can say "I'm awake"
     to stop the alarm; all processing is on-device.

  Note on export: a parent can optionally export their own recordings / wake-up
  history via the standard iOS share sheet (this action is placed behind a parental
  gate). This is parent-initiated data portability to a destination the parent
  chooses; the data is never sent to us or any third party, so it is not "collection".

The app has no account, no login, no server, and does not use IDFA/AppTrackingTransparency.
Our App Privacy is set to "Data Not Collected", consistent with our COPPA-compliant
privacy policy: https://rexcode.app/sunny_walker/privacy/
```

## 佐證（已對 code 核實）
- 無 `URLSession` / 任何對外網路請求（全離線）
- 無 Firebase / Crashlytics / AdMob / 任何 analytics / ad SDK
- 無 IDFA / `ATTrackingManager`
- 第三方套件僅 `ConfettiSwiftUI`（純 UI 動畫，不收資料）
- 資料皆存裝置本機（SwiftData / UserDefaults / Documents/Recordings）
