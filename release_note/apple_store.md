# SunnyWalker — App Store Release Note

| 欄位 | 值 |
|---|---|
| App | SunnyWalker |
| Bundle ID | `app.rexcode.sunnywalker` |
| 顯示版本 (Marketing Version) | **1.0.20260610** |
| Build (CFBundleVersion) | **4** |
| 送審日期 | 2026-06-10 |
| 類別 | Education（Made for Kids，年齡帶 6–8） |
| 前次紀錄 | 1.0 (2) 於 2026-06-09 被退（Guideline 4 權限語言 + 2.3.8 metadata），本次為修正後重送 |

> ⚠️ Archive 前把 `20260610` 改成實際打包當天日期；ASC 版本頁 Version 欄位同步改成相同字串。

---

## App Store「版本說明 / What's New」

> 首發版本（1.0 train）。App Store 對首次上架不一定要求版本說明，可填以下文字，或先留白。

### 繁體中文（zh-Hant）

```
SunnyWalker 是一款專為小朋友設計的暖心鬧鐘。

‧ 爸媽可以錄下自己的聲音，溫柔地把孩子叫醒
‧ 鎖屏、靜音也照響，不錯過上學時間
‧ 孩子說出「我起床了」就能關掉鬧鐘，養成自己起床的習慣
‧ 起床後有可愛的獎勵動畫，讓早晨變得期待

100% 離線、無廣告、不收集任何資料，錄音只留在你的裝置裡。
```

### English (en)

```
SunnyWalker is a gentle wake-up alarm made for young children.

• Parents can record their own voice to wake their child up warmly
• Rings even on the Lock Screen and in Silent mode, so school mornings stay on time
• The child says "I'm awake" to turn the alarm off, building a healthy wake-up habit
• A cheerful reward animation makes mornings something to look forward to

100% offline, no ads, and no data collected — recordings stay on your device.
```

---

## 宣傳文字 / Promotional Text（選填，≤170 字元，可隨時改不需重審）

- 繁中：`爸媽的聲音當鬧鈴，孩子說「我起床了」就關掉。鎖屏靜音照響、完全離線、零廣告。`
- EN：`Wake your child with your own voice. They say "I'm awake" to stop it. Rings on Lock Screen & Silent, fully offline, zero ads.`

---

## Resolution Center 回覆（英文，貼回 App Store Connect）

```
Thank you for the feedback on build 1.0 (2).

1. Guideline 4 (Design): All permission usage descriptions (alarm, microphone,
   speech recognition) are now localized into both English and Traditional
   Chinese, so the dialogs always match the app's UI language.

2. Guideline 2.3.8 (Metadata): The app's Age Rating is now set to "Made for
   Kids" (ages 6–8), so the audience and category are consistent. The app
   collects no data and contains no third-party analytics or advertising; all
   microphone and speech processing happens on-device. Every outbound link and
   share/export action sits behind a parental gate. A COPPA-compliant privacy
   policy is provided at https://rexcode.app/sunny_walker/privacy/.

A new build (1.0.20260610 (4)) has been submitted with these fixes.
```

---

## 送審前最終確認（後台）

- [ ] Age Rating → Made for Kids，年齡帶 6–8
- [ ] App Privacy → **Data Not Collected**（若先前填過 Audio Data = Yes 要改回）
- [ ] Privacy Policy URL：`https://rexcode.app/sunny_walker/privacy/`（已確認含 COPPA / 不收集資料 / parental gate）
- [ ] Version 欄位填 `1.0.20260610`，上傳後選 build 4
- [ ] 英文 iPad 實測：權限框英文、App 在 iPad 正常
- [ ] Resolution Center 貼上上方回覆
