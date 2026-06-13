# SunnyWalker — App Store Release Note

## 1.1.20260612 (build 9) — 溫和提醒模式（per-alarm Time-Sensitive 通知）

| 欄位 | 值 |
|---|---|
| 顯示版本 (Marketing Version) | **1.1.20260612**（新功能 → MINOR bump） |
| Build (CFBundleVersion) | **9**（6、7 被 1.0.20260612 佔用；8 缺 i18n 修正已上傳作廢——英文版會出現中文，ASC 版本頁換掛 build 9 即可） |
| 送審日期 | 2026-06-12 |
| 前次紀錄 | 1.0.20260612 (7) 同日送審（錄音頁優化）；若仍在審需先 Remove from Review |
| 本次重點 | per-alarm「溫和提醒模式」（Time-Sensitive 通知，響 30 秒自動停）；錄音 loop 填滿 30s + 輪間靜音；通知 body 顯示鬧鐘 label；點通知回主畫面不開關鬧鐘畫面；修復 entitlement 未進 binary 造成通知整顆被丟（issue/fix_issue__NOTIFICATION_MODE_NOT_FIRING.md） |
| ASC 文案 | **What's New / Description / Keywords / Subtitle 中英文全套見 `docs/for_Apple_store/20260612_appstoreconnect_content.md`** |

> ⚠️ Archive 前必跑 `xcodegen generate`（本次 entitlement 之雷即漏跑此步）。
> 裝機抽查：設定 ▸ SunnyWalker ▸ 通知內頁要有「Time Sensitive」開關才代表 entitlement 在 binary。

---

## 1.0.20260612 (build 7) — 錄音頁優化 + 在地化修正

| 欄位 | 值 |
|---|---|
| App | SunnyWalker |
| Bundle ID | `app.rexcode.sunnywalker` |
| 顯示版本 (Marketing Version) | **1.0.20260612** |
| Build (CFBundleVersion) | **7** |
| 送審日期 | 2026-06-12 |
| 類別 | Education（Made for Kids，年齡帶 6–8） |
| 前次紀錄 | 1.0.20260610 (4) 於 2026-06-10 核准上架；本次為功能更新 |
| ⚠️ Build 歷史 | build 6 已被一次上傳佔用（ASC 已有 1.0.20260612 (6)，code 90189 Redundant Binary）→ 改用 build 7 重新 archive |
| 本次重點 | 錄音／命名／試聽整合為單頁；新增「重新錄音」；自動命名長度上限（中文 8、英文 16）；補上英文版缺漏字串，修正中英混排（避免 App Review 退件） |

> ⚠️ Archive 前已把 `MARKETING_VERSION` 改成 `1.0.20260612`、build 改成 7；改完 `project.yml` 記得 `xcodegen generate` 再打包。ASC 需「+ Version」開一個 1.0.20260612 新版本，附 build 7，填 What's New 後送審（更新版必填版本說明）。

### App Store「版本說明 / What's New」

#### 繁體中文（zh-Hant）

```
這次更新讓「錄音」變得更簡單好用：

‧ 錄音、命名、試聽整合在同一頁，一次就能完成
‧ 新增「重新錄音」按鈕，不滿意可以立刻重錄
‧ 「辨識錄音內容」會自動幫錄音取名字
‧ 修正部分介面文字，整體更順手

謝謝你陪 SunnyWalker 一起長大 ☀️
```

#### English (en)

```
This update makes recording your voice simpler and smoother:

• Record, name, and preview are now all on one page
• A new "Record again" button lets you instantly redo a take
• "Name from voice" automatically names your recording for you
• Polished interface text for a cleaner, smoother experience

Thanks for growing up with SunnyWalker ☀️
```

### 送審前最終確認（本次更新）

- [ ] `project.yml`：MARKETING_VERSION `1.0.20260612`、CURRENT_PROJECT_VERSION `7`
- [ ] `xcodegen generate` 後再 Archive（Any iOS Device / arm64）
- [ ] Xcode Organizer → Distribute → App Store Connect → Upload（build 7）
- [ ] ASC「+ Version」建立 `1.0.20260612`，附 build 7
- [ ] 貼上上方 What's New（中／英）
- [ ] Age Rating、App Privacy（Data Not Collected）、Privacy Policy URL 沿用前版即可
- [ ] Submit for Review（Made for Kids 更新仍需審核，不會自動發佈）

---

## 歷史版本

### 1.0.20260610 (build 4) — 首發核准

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
