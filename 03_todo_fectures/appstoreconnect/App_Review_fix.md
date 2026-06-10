# SunnyWalker 1.0 (2) 被退件分析與修法

> Submission ID: `8fa0d89a-a699-45fa-843a-189301c53e3b`
> Review date: 2026-06-09 ‧ Review device: iPad Air 11-inch (M3) ‧ Version: 1.0 (2)
> 兩條退件理由：**Guideline 4 - Design**（權限語言不一致）＋ **Guideline 2.3.8 - Accurate Metadata**（"for kids" 字眼）
>
> **決策：理由 2 走「Made for Kids」**（扛 COPPA / parental gate）。
> 本文件＝實作 spec：分析在前、可直接照〈給實作者（Sonnet）的待辦〉逐步執行；所有程式碼判斷均已對照 source 驗證。

---

## 退件理由 1 — Guideline 4 (Design)：權限提示語言和 App 在地化不一致

### Apple 怎麼說

> the app includes permissions requests that are **not written in the same language as the app's localization**.

附圖就是證據：審核員在 **英文語系的 iPad** 上跑 App。

- App 的「介面」顯示英文（時間 `12:31 AM`、`Tuesday, 9 Jun`、提示文字 `Tap the + at the bottom right...`）
- 但麥克風權限對話框 **內文卻是中文**（「鬧鐘需要聽你說『我起床了』才能播放…只留在這台 iPhone 裡」）

→ 介面英文、權限中文 → Apple 認定品質不一致，退件。

### 真正的 root cause（已對照專案確認）

App **本身有做雙語在地化**，但 **權限字串漏掉在地化**：

| 項目 | 狀態 |
|------|------|
| App UI 文案 `Localizable.xcstrings` | ✅ 已含 `en` + `zh-Hant`，共 236 條 |
| `knownRegions` (pbxproj) | ✅ `Base, en, zh-Hant` |
| `developmentRegion` | `zh-Hant` |
| 三條權限字串（`NS*UsageDescription`） | 🔴 **只有寫死的中文，沒有任何 InfoPlist 在地化檔** |

問題出在 `project.yml` 的 `info.properties` 把三條權限字串寫死成中文：

```yaml
NSAlarmKitUsageDescription: "SunnyWalker 需要鬧鐘權限，才能在鎖屏和靜音模式下叫醒小朋友。"
NSMicrophoneUsageDescription: "鬧鐘需要聽你說「我起床了」才能關掉喔！聲音只留在這台 iPhone 裡，不會傳出去。"
NSSpeechRecognitionUsageDescription: "用來聽懂你說的話，把鬧鐘關掉。所有辨識都在這台裝置上完成。"
```

`Info.plist` 裡的 `NS*UsageDescription` 是「最後保底字串」，**只有一種語言**。當裝置設成英文、且找不到對應的 `en` 在地化權限字串時，iOS 就直接顯示這個保底的中文 → 和英文 UI 撞在一起。

### 修法（推薦：用 InfoPlist String Catalog，最乾淨）

關鍵：權限字串要跟 UI 一樣，提供 `en` 和 `zh-Hant` 兩種版本。三種做法擇一。

#### 做法 A（推薦）— 新增 `InfoPlist.xcstrings` String Catalog

1. 在 Xcode 對 `SunnyWalker` target → File ▸ New ▸ File ▸ **String Catalog**，命名 `InfoPlist`，存到 `SunnyWalker/InfoPlist.xcstrings`。
2. 加入三個 key：`NSAlarmKitUsageDescription`、`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`。
3. 各填 `zh-Hant`（沿用現有中文）與 `en` 翻譯。建議英文版（語氣與中文一致、且強調「只在本機」以利後面 2.3.8 與隱私審查）：

   | Key | English |
   |-----|---------|
   | `NSAlarmKitUsageDescription` | `SunnyWalker needs alarm permission so it can wake you up even when your device is locked or on silent.` |
   | `NSMicrophoneUsageDescription` | `The alarm listens for you to say "I'm awake" so it can turn off. Audio stays on this device and is never sent anywhere.` |
   | `NSSpeechRecognitionUsageDescription` | `Used to recognize what you say so the alarm can be turned off. All recognition happens on-device.` |

4. 因為 xcodegen 的 `sources` 指向整個 `SunnyWalker/` 資料夾，新增的 `InfoPlist.xcstrings` 會被自動納進 resource，不必改 `project.yml`。

#### 做法 B — 傳統 `InfoPlist.strings`（不想用 String Catalog 時）

新增兩個檔案（內容用 `"key" = "value";`）：

`SunnyWalker/en.lproj/InfoPlist.strings`
```
"NSAlarmKitUsageDescription" = "SunnyWalker needs alarm permission so it can wake you up even when your device is locked or on silent.";
"NSMicrophoneUsageDescription" = "The alarm listens for you to say \"I'm awake\" so it can turn off. Audio stays on this device and is never sent anywhere.";
"NSSpeechRecognitionUsageDescription" = "Used to recognize what you say so the alarm can be turned off. All recognition happens on-device.";
```

`SunnyWalker/zh-Hant.lproj/InfoPlist.strings`
```
"NSAlarmKitUsageDescription" = "SunnyWalker 需要鬧鐘權限，才能在鎖屏和靜音模式下叫醒小朋友。";
"NSMicrophoneUsageDescription" = "鬧鐘需要聽你說「我起床了」才能關掉喔！聲音只留在這台 iPhone 裡，不會傳出去。";
"NSSpeechRecognitionUsageDescription" = "用來聽懂你說的話，把鬧鐘關掉。所有辨識都在這台裝置上完成。";
```

`Info.plist` 裡那三條保底字串可以保留（當成 `developmentRegion = zh-Hant` 的 fallback），iOS 會優先用符合裝置語系的 `InfoPlist.strings`。

> ⚠️ xcodegen 注意：`.lproj/InfoPlist.strings` 在 `SunnyWalker/` 底下會被當 resource 自動收進去；`xcodegen generate` 後到 target ▸ Build Phases ▸ Copy Bundle Resources 確認兩個 `InfoPlist.strings` 都有列入、且 build 後 `.app/en.lproj/` 與 `.app/zh-Hant.lproj/` 裡都有檔。

#### 做法 C — 只想最快過審（治標）

如果這次只想單純讓英文裝置不再出現中文：把 `Info.plist` 的三條保底字串改成「英文」（最通用），再靠做法 A/B 補回中文。但 **長期還是建議做 A**，否則中文使用者反而看到英文權限，治標不治本。

### 驗收方式

1. 模擬器或實機 Settings ▸ General ▸ Language & Region 設成 **English**。
2. 重裝 App、觸發鬧鐘 → 第一次跳麥克風/語音/鬧鐘權限時，對話框內文應為 **英文**。
3. 再把語系切回 **繁體中文** 重測 → 內文應為中文。
4. 兩種語系下 UI 與權限語言一致即過關。

---

## 退件理由 2 — Guideline 2.3.8 (Accurate Metadata)：subtitle 出現 "for kids"

### Apple 怎麼說

> the app **subtitle** … includes the term **for kids**, which implies that this app is made specifically for children. However, this app was **not submitted as a Kids category app**.

被標記的素材：App Store Connect 上的 **subtitle**，連帶要檢查 **app name / icon / screenshots**（被點名的檔 `Screenshot-0609-153105.png`）。

重點：Apple 不是說「不能做給小孩的 App」，而是說「你在文案/截圖暗示主要受眾是兒童，卻沒把 App 歸到 Kids 類別」——**宣稱與分類不一致**。

### 決定：走路線 2（Made for Kids）

> ✅ **已拍板：正式把 SunnyWalker 歸到「Made for Kids」類別**，扛 COPPA / parental gate。
> 詳細技術實作見下方〈Made for Kids 技術實作細節〉。路線 1 保留作對照。

### 兩條路

#### 路線 1（對照組）— 拿掉暗示兒童的字眼，維持一般類別

在 App Store Connect ▸ App 資訊 / 該版本頁面：

1. **Subtitle**：移除 `for kids` / `for children` / `kids` 等字。改成描述「功能」而非「受眾」。例如：
   - ❌ `A gentle alarm for kids`
   - ✅ `A gentle wake-up alarm` 或 `Wake up with a calm, friendly alarm`
2. **App Name / Icon / Screenshots**：同步檢查有沒有 "kids / children / 兒童 / 小朋友" 字樣或明顯只針對幼兒的標語，一併拿掉或改成中性描述。
3. App 內部 UI 文案出現「小朋友」沒關係（那是內容，不是商店 metadata），審核針對的是 **商店端 metadata**；但若截圖把這些文案放大當賣點，建議換一張。

> （對照組）此路線改動最小、不必扛 Kids 類別的法規負擔，但放棄了主打兒童的定位。本次**不採用**。

#### 路線 2 — 正式歸到「Made for Kids」類別

若你真的想以兒童為主打受眾，可在 App Store Connect ▸ App 資訊 ▸ **Age Rating** 區塊勾選 **Made for Kids**，並選擇年齡帶（5 以下 / 6–8 / 9–11）。但要先滿足 Kids 類別的硬性要求：

- 不得收集個資、不得有行為廣告 / 第三方分析追蹤；任何外部連結、購買、跨 App 行為都要放在 **parental gate** 後面。
- 隱私政策要符合兒童規範（COPPA / GDPR-K）。

> ✅ **本次採用此路線。** SunnyWalker 麥克風/語音都標榜「只在本機、不外傳」，本來就高度符合 Kids 規範；代價是審查更嚴、日後維護需持續守住「零第三方追蹤 + 重要出口 gate」這條線。具體實作見下方〈Made for Kids 技術實作細節〉。

### 驗收方式

- Subtitle、name、icon、被點名截圖都不再出現 kids/children/兒童 等受眾字眼（走路線 1），或
- Age Rating 已勾 Made for Kids 且滿足上述要求（走路線 2）。

---

## Made for Kids 技術實作細節（路線 2）

> Apple Kids 類別的硬性規範（Guideline 1.3 + 5.1.4 + App Review Guidelines「Kids Category」）：
> **(a)** 不得含第三方廣告與第三方分析；**(b)** 任何「離開 App / 商業行為 / 送出個資」前必須先過 **parental gate**；
> **(c)** 必須符合 COPPA / GDPR-K，提供隱私政策 URL；**(d)** 不得使用 IDFA / AppTrackingTransparency。
> 以下逐項對照 SunnyWalker 現況（已掃過 source 確認）。

### 1. 第三方 SDK / 廣告 / 分析 — ✅ 目前合規，維持即可

掃描結果：

| 檢查項 | 結果 |
|--------|------|
| 第三方分析（Firebase / Crashlytics / Mixpanel / AppsFlyer / Sentry…） | ✅ 完全沒有 |
| 廣告 SDK（AdMob / GADBanner…） | ✅ 沒有 |
| IDFA / `ATTrackingManager` | ✅ 沒有 |
| 第三方套件 | 只有 `ConfettiSwiftUI`（純 UI 動畫，不收資料）✅ |
| 任何 `URLSession` / 對外網路請求 | ✅ 沒有（全離線）|

→ **動作：保持「零第三方追蹤」。** 之後若想加 crash / analytics，Kids 類別只能用「不會把兒童資料送給第三方」的方案，或乾脆不加。新增任何 SPM 套件前先確認它不含廣告/追蹤。

### 2. Parental Gate — ⚠️ 已有元件，但覆蓋面與在地化要補

現況：`SunnyWalker/Views/Settings/ParentalGateView.swift`（Day 6 就做了）已存在，題庫含三類：星期排序、最大數字、三位數乘法；答錯 3 次會抖動。Settings 入口已經 gated（`showingParentalForSettings`）。

#### 2-1. Gate 必須覆蓋「所有離開 App / 送出資料」的出口

**現況（已實際追過呼叫鏈，確認無誤）：** 三個會把資料送出 App 的 share/export 出口，全都位在 `SettingsView` 內，而 `SettingsView` 只有在 parental gate 通過後才會開啟（`HomeView` 設定鈕 → `showingParentalForSettings` → `ParentalGateView` onSuccess → `showingSettings` → `SettingsView`）。所以它們**已經被 gate 保護一層**：

| 出口 | 檔案 / 觸發點 | 行為 |
|------|--------------|------|
| 錄音管理分享 | `VoiceLibraryView.swift`（`ShareLink(item: clip.recordingsURL …)`，約 L626） | 把錄音檔送到其他 App |
| 匯出鬧鐘 Markdown | `AlarmIOView.swift`（`ShareLink("分享 / 匯出 Markdown" …)`，約 L29） | 透過 share sheet 送出資料 |
| 起床紀錄匯出 .md | `WakeHistoryView.swift`（存 `.md` 到「檔案」App，約 L46） | 資料離開 App |

> ⚠️ **風險點**：parental gate 一旦通過、`SettingsView` 開著，家長把手機交回小孩後，小孩就能在設定頁內直接點這些分享鈕。Apple 審核**有時**會要求「就在離開/分享動作當下再 gate 一次」。
>
> **判斷**：目前「設定頁入口 gate 一次」是業界常見且多半會過的做法，**可先這樣送審**，並在回覆信中明確說明「所有分享/匯出功能都位於需通過家長驗證才能進入的設定頁內」。**若這次又被以此點退件**，再對三個 `ShareLink`／匯出按鈕外層各包一層 `ParentalGateView`（成本不高）。不必一開始就過度加 gate。
>
> 反例（刻意不 gate，且正確）：`HomeView` 的語言切換鈕——切語言不離開 App、不送資料，依規範本就不需要 gate。

#### 2-2. Gate 題目要「小孩答不出來」且要在地化

- 🔴 **題庫太簡單的要拿掉。** 「星期排序」「哪個數字最大」對 6–8 歲小孩太容易，Apple 可能不認。**建議只保留三位數乘法那組**（`127 × 4`、`236 × 3`、`154 × 5`），或改成 Apple 慣見的「請輸入下列數字／按住 N 秒後輸入答案」。
- 🔴 **乘法題缺英文在地化（撞 Guideline 4）。** 掃描 `Localizable.xcstrings`：星期/最大數字題、`請大人來幫忙`、`取消` 都有 `en`，但 **`127 × 4 = ？` 等乘法 prompt 完全沒進 xcstrings**。雖然它只有數字+符號、英文裝置上還是讀得懂，但為了一致性與保險，請把乘法 prompt 也加進 string catalog（或改用純算式不需翻譯的呈現）。
- gate 內所有字串（含未來新增題）都要 en + zh-Hant 兩版，跟退件理由 1 的修法一致。

#### 2-3. 未來的 Pro / IAP 也要 gate

`Services/AppSettings.swift` 有 `isPro`（目前恆 false，尚未接 StoreKit）。**一旦接上 StoreKit / 內購 / 任何付費，購買入口必須先過 parental gate**，否則違反 Kids 規範。現在沒接 → 暫無風險，但先記著。

### 3. 隱私 / COPPA — App Privacy 標籤宣告「不收集資料」

SunnyWalker 的資料全部留在裝置（SwiftData：`Alarm` / `WakeRecord` / `VoiceClip` / `WakePhrase`；麥克風與語音辨識都標榜 on-device、不外傳；無網路請求、無登入）。對 Kids 類別這是最理想狀態。

App Store Connect 要設定：

1. **App Privacy（隱私營養標籤）**：據實勾選 **Data Not Collected**（不收集任何資料）。這是 Kids 類別最安全的宣告，且和程式碼現況一致。
   - ⚠️ 別誤勾。麥克風/語音雖會「使用」，但只要不離開裝置、不關聯身分，就屬「使用而非收集」，仍可宣告 Data Not Collected。
2. **隱私政策 URL（必填）**：Made for Kids 一定要有可公開存取的隱私政策網址，內容需說明：不向 13 歲以下兒童收集個資、麥克風/語音僅在本機處理、無第三方分享、無廣告。可掛在你現有的 Cloudflare Pages 網站新增一頁。
3. **不得要求登入或個資**：現況無登入 ✅，維持。
4. **App Store Connect ▸ Age Rating ▸ 勾「Made for Kids」**，選年齡帶（5 以下 / 6–8 / 9–11）。SunnyWalker 訴求學齡兒童，建議 **6–8**。

### 4. App Store Connect 後台設定清單（路線 2）

1. **Age Rating**：完成問卷 → 勾 **Made for Kids** → 選年齡帶（建議 6–8）。
2. **Category**：主類別維持（如 Education / Lifestyle / Utilities 皆可），Made for Kids 是獨立旗標、不必改成 Kids 主類別也行；但勾了 Made for Kids 後就要全面符合上述規範。
3. **Privacy Policy URL**：填上線網址。
4. **App Privacy**：Data Not Collected。
5. **Subtitle / 截圖**：因為現在「正大光明訴求兒童」，subtitle 可保留「for kids」之類字眼——但要確保和 Made for Kids 旗標一致（Apple 退的是「宣稱兒童卻沒勾 Kids」，現在勾了就一致了）。

> 小結：路線 2 對程式碼的主要改動是 **(a) 三個 ShareLink/匯出出口補 parental gate、(b) gate 題庫精簡為高難度且全在地化**；後台則是 **勾 Made for Kids + 隱私政策 URL + Data Not Collected**。第三方追蹤本來就沒有，是最大的利多。

---

## 給實作者（Sonnet）的待辦：依序執行

> 決策已定：**走 Made for Kids**。以下是「程式碼端」要動的，按順序做即可；後台（App Store Connect）的設定見上方第 4 節，由人到網頁操作。
> 開工前依 `CLAUDE.md` 慣例先 `vein_brief()` / `vein_recall("swift ios localization infoplist kids parental gate")`，改完用 `git diff` 自檢並 `vein_log` 記錄。

**Step 1 — 權限字串在地化（解退件理由 1，必做）**
- 採做法 A：新增 `SunnyWalker/InfoPlist.xcstrings`，含 `NSAlarmKitUsageDescription` / `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` 三個 key，各填 en + zh-Hant（中文沿用 `project.yml` 現值，英文用第 1 節表格）。
- `project.yml` 的 `info.properties` 三條中文字串**保留**當 fallback；不需改 `project.yml` 結構（sources 已涵蓋整個 `SunnyWalker/`）。
- 跑 `xcodegen generate`，確認 `InfoPlist.xcstrings` 進了 target 的 Copy Bundle Resources。

**Step 2 — Parental gate 題庫精簡 + 在地化（Made for Kids 必做）**
- 檔案：`SunnyWalker/Views/Settings/ParentalGateView.swift`。
- 把 `allTemplates` 改成**只用 `multiplicationQuestions`**（移除 `weekdayQuestions`、`largestNumberQuestions`，那兩組對 6–8 歲太簡單）。
- 把三條乘法 prompt（`127 × 4 = ？`、`236 × 3 = ？`、`154 × 5 = ？`）補進 `Localizable.xcstrings`（en + zh-Hant；英文可直接用相同算式字串）。選項是純數字，無需翻譯。

**Step 3 — 確認無第三方追蹤（Made for Kids 必做，目前已通過）**
- 已掃描：無 Firebase/Crashlytics/AdMob/IDFA/`URLSession`，第三方套件只有 `ConfettiSwiftUI`。**維持現狀即可**；本步驟只需在 PR 前再 `grep` 複查一次，別讓新 code 引入追蹤。

**Step 4 — share/export 出口（先不動，視審核結果再決定）**
- 三個出口（`VoiceLibraryView` / `AlarmIOView` / `WakeHistoryView`）已在 gated 的 `SettingsView` 內，**本次先不加第二層 gate**（見第 2-1 節判斷）。
- 僅在「再次因 parental gate 被退」時，才對這三處 `ShareLink`／匯出按鈕各外包一層 `ParentalGateView`。

**Step 5 — 版本號（2026-06-10 已改成對齊 Lode 的版號規則）**
- ✅ 已完成：`project.yml` 現為 `MARKETING_VERSION: "1.0.20260610"`、`CURRENT_PROJECT_VERSION: 4`；`Info.plist` 改用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 引用，single source。
- 顯示版本從原本的 `1.0` 改成 **`1.0.20260610`**（marketing=MAJOR.MINOR.YYYYMMDD，與 Lode `0.5.20260605` 同規則），build = **`4`**（被退的是 build 2；新 build 用 4，>2 即可）。
- ⚠️ Archive 前把日期段 `20260610` 改成實際 archive 當天。
- ⚠️ **App Store Connect 端**：原本被退的版本記錄是「1.0」。因為改了顯示版本，要到該版本頁把 **Version 欄位從 `1.0` 改成 `1.0.20260610`**（app 尚未上架、可直接改），上傳後選 build 4。若懶得改，也可把 `MARKETING_VERSION` 改回 `1.0`、只 bump build——但那就不跟 Lode 一致了。

**Step 6 — 驗證**
- `xcodegen generate` → build → 英文/中文兩語系各跑一次（見第 1 節驗收 + 確認 gate 在兩語系都正確顯示）。
- `git diff` 逐條對照本清單，確認沒有動到不該動的檔。

---

## 重新送審前 checklist

**理由 1（Guideline 4 權限語言）**

- [ ] 三條 `NS*UsageDescription` 已提供 `en` + `zh-Hant` 在地化（做法 A 或 B）
- [ ] 英文裝置實測：權限對話框內文為英文；中文裝置為中文

**理由 2（Made for Kids，走路線 2）**

- [ ] 程式碼：gate 題庫精簡為只留三位數乘法（移除星期/最大數字），乘法 prompt 已補進 `Localizable.xcstrings`（en + zh-Hant）
- [ ] 程式碼：確認無第三方廣告/分析/IDFA（目前 ✅，新增套件時複查）
- [ ] （已確認）三個 share/export 出口位於 gated 的 `SettingsView` 內，本次不加第二層 gate；僅在再次被退時才補
- [ ] 後台：Age Rating 已勾 **Made for Kids**，年齡帶選 6–8
- [ ] 後台：已填可公開存取的 **Privacy Policy URL**（說明不收集兒童個資、語音僅在本機）
- [ ] 後台：App Privacy 設為 **Data Not Collected**

**共同**

- [x] 版本號已對齊 Lode：顯示版本 `1.0.20260610`、build `4`（被退的是 2）。⚠️ ASC 版本頁的 Version 欄位記得也從 `1.0` 改成 `1.0.20260610`
- [ ] 回覆 App Store Connect 的 Resolution Center，簡述兩點都已修正

> 回覆 Apple 範例（英文）：
> *"Thank you for the feedback. (1) We have localized all permission usage descriptions (microphone, speech recognition, alarm) into English and Traditional Chinese so they always match the app's UI language. (2) We have set the app's Age Rating to 'Made for Kids' (ages 6–8). The app collects no data and contains no third-party analytics or advertising; all microphone and speech processing is on-device. Outbound sharing/export actions are placed behind a parental gate, and a privacy policy compliant with COPPA is provided. A new build (1.0 (3)) has been submitted."*
