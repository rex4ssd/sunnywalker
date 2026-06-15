# SunnyWalker — App Store Release Note

## 1.3.20260615 (build 13) — 修內建鈴聲 + 從檔案匯入音檔當鈴聲（承接 Pro IAP）

> 📦 **同一顯示版本 `1.3.20260615` 同日多次打包**：build 11(放棄)、build 12(已上傳，僅 bug fix)、
> **本版 build 13** 在 build 12 之上再加「從檔案匯入音檔當鈴聲」新功能 → **以 build 13 送審**，
> build 12 由 build 13 取代（同版本頁改掛 build 13 即可）。What's New 涵蓋 Pro + bug fix + 匯入功能。

| 欄位 | 值 |
|---|---|
| 顯示版本 (Marketing Version) | **1.3.20260615**（沿用 1.3 Pro train，只換打包日期） |
| Build (CFBundleVersion) | **13**（11、12 皆已上傳佔用 → 進 13） |
| 送審日期 | 2026-06-15 |
| 前次紀錄 | 1.3.20260615 (12) — 已上傳（bug fix）；1.3.20260614 (11) — 已上傳後放棄；1.2.20260613 (10) — 免費版 |
| Bundle ID | `app.rexcode.sunnywalker`　/　ASC App ID `6775802674`　/　Team `NHY8MKW8NH` |
| 內含 | 承接 SunnyWalker Pro（NT$50 終身 IAP、家庭共享、grandfather 自動免費升級）＋下列修正與新功能 |

### 🐞 本版修正

- **內建鈴聲在「溫和提醒（通知）模式」終於會響。** 之前選內建鈴聲（陽光起床／樹葉沙沙）在通知模式只會「咚」一聲系統預設音、聽不到內建鈴聲本身——root cause 是 `AlarmScheduler` 的選音邏輯只替「自錄聲」設真正的 `UNNotificationSound`，內建鈴聲一律落到 `.default`。本版新增內建鈴聲分支：把 bundle 內 18–20s 的 CAF 修剪成 4.5s 短 CAF（避開 iOS「長自訂通知音鎖屏退成 ~2s」的雷），再交給既有的「切段響滿 30 秒」堆疊機制鋪滿。自錄聲行為不變。
  - 改動檔：`SunnyWalker/Services/AlarmScheduler.swift`（新增 `isBundledSelection` 分支）、`SunnyWalker/Services/AudioRecorder.swift`（新增 `AlarmSoundExporter.exportBundledShortCAF`）。

### ✨ 本版新功能

- **從「檔案」匯入手機內音檔當鈴聲。** 在「選鈴聲」與「錄音管理」新增「匯入音檔」：用 `.fileImporter` 從 檔案 App／iCloud Drive 選 mp3/wav/m4a/aiff → security-scoped 複製到 tmp → `AVAssetExportSession`（AppleM4A、iOS 18+ 的 `export(to:as:)`）轉檔並從頭裁到長度上限 → 存成 `Documents/Recordings/<UUID>.m4a`，與錄音同佈局，下游（清單／試聽／設為鈴聲／通知音 CAF／切段堆疊）全部沿用。裁切＝取前 N 秒（免費 5s／Pro 30s）；匯入算進「自訂鈴聲 5 個」同一上限。⚠️ DRM 保護的歌（Apple Music／iTunes 購買）匯不進來，會跳友善錯誤。
  - 新增檔：`SunnyWalker/Services/AudioImporter.swift`。改動：`RingtonePickerSheet.swift`、`VoiceLibraryView.swift`（各加「匯入音檔」鈕 + 錯誤 alert）、`Localizable.xcstrings`（中英字串）。
  - ⚠️ **有新增檔** → Archive 前**務必** `xcodegen generate` 把 `AudioImporter.swift` 註冊進 pbxproj，否則不會編進 target。

### App Store「版本說明 / What's New」

#### 繁體中文（zh-Hant）

```
SunnyWalker Pro 來了，還能用你自己的音檔當鈴聲 ✨

‧ 新增：可以從「檔案」匯入手機裡的音檔（mp3／wav 等）當叫醒鈴聲
‧ 修正：在「溫和提醒」模式選用內建鈴聲時，現在會正確響起鈴聲（先前只會響一聲系統提示音）
‧ SunnyWalker Pro：一次購買、永久解鎖——鬧鐘數量、自定鈴聲數量與長度、爸媽錄音長度全部無上限
‧ 支援家庭共享，一人購買、全家共用；購買入口放在「設定」的家長驗證之後，孩子不會誤觸
‧ 感謝老朋友：已經在用 SunnyWalker 的你，更新後直接免費獲得 Pro ☀️

基本的叫醒功能永遠免費。完全離線、零廣告、不收集任何資料。
```

#### English (en)

```
Meet SunnyWalker Pro — and set your own audio as a ringtone ✨

• New: import an audio file from Files (mp3, wav, and more) to use as a wake-up sound
• Fixed: built-in ringtones now play correctly in Gentle Reminder mode (previously you'd only hear a single system alert tone)
• SunnyWalker Pro: one-time purchase, unlocked forever — unlimited alarms, unlimited voice clips, longer clips, and longer parent recordings
• Family Sharing supported; the upgrade lives in Settings behind a parental gate so kids can't tap to buy
• Thank you to our early friends: if you already use SunnyWalker, this update unlocks Pro for you for free ☀️

The core wake-up features stay free forever. Fully offline, zero ads, no data collected.
```

### 送審前最終確認（本次更新）

- [ ] `project.yml`：MARKETING_VERSION `1.3.20260615`、CURRENT_PROJECT_VERSION `13` → **`xcodegen generate`**（套版號 **+ 註冊新檔 `AudioImporter.swift`**）
- [ ] 真機驗收新功能：選鈴聲／錄音管理 → 匯入音檔 → 挑一首 mp3 → 出現在自訂鈴聲、可試聽、可設為鬧鈴；到 5 個上限時鈕變鎖頭；DRM 歌曲跳友善錯誤
- [ ] 真機驗收 bug fix：溫和提醒模式 + 內建鈴聲 → 殺 App／關屏 → 應聽到內建鈴聲（非「咚」一聲）；切段堆疊正常；自錄聲不變
- [ ] 真機驗收 IAP：設定 → 家長驗證後才看得到「SunnyWalker Pro」→ 購買 → 上限解除；Restore 可還原；grandfather 舊用戶自動免費
- [ ] App Store Connect：`1.3.20260615` 版本頁改掛 **build 13**，貼上方 What's New
- [ ] Age Rating（Made for Kids 6–8）、App Privacy（Data Not Collected）、Privacy Policy URL 沿用
- [ ] Xcode Organizer → Distribute → Upload（build 13）→ Submit（首個 IAP 隨 binary 一併送審）

---

## 1.3.20260615 (build 12) — 修復內建鈴聲在溫和提醒模式不響（承接 Pro IAP）　⚠️ 已上傳，由 build 13 取代（加匯入音檔）

> 🐞 已上傳 ASC，但隨即由 **build 13**（再加「匯入音檔」功能）取代。內容＝SunnyWalker Pro + 內建鈴聲通知音修正。

---

## 1.3.20260614 (build 11) — SunnyWalker Pro（NT$50 終身解鎖 IAP）　⚠️ 已上傳後放棄，由 1.3.20260615 (build 13) 取代

> 💰 **本次為「付費解鎖版」**：合併 `feature/pro-iap-lifetime` 的 StoreKit 2 一次性買斷
> （non-consumable，家庭共享）。免費版叫醒功能不變；Pro 解除四個上限。
> ⚠️ 既有用戶（裝過舊版）會被 **grandfather 自動免費升 Pro**，只有全新安裝才付費。

| 欄位 | 值 |
|---|---|
| 顯示版本 (Marketing Version) | **1.3.20260614**（新功能「SunnyWalker Pro」→ MINOR bump；main 已用掉 1.2，故進 1.3） |
| Build (CFBundleVersion) | **11**（10 已被 1.2.20260613 佔用） |
| 送審日期 | 2026-06-14 |
| 前次紀錄 | 1.2.20260613 (10) — 免費版（切段 30s + 錄音管理） |
| Bundle ID | `app.rexcode.sunnywalker`　/　ASC App ID `6775802674`　/　Team `NHY8MKW8NH` |
| IAP Product ID | `app.rexcode.sunnywalker.pro.lifetime`（Non-Consumable，Family Shareable） |
| 價格 | **NT$50（≈ US$1.49）一次買斷** — `.storekit` displayPrice 1.49；實際價格在 ASC 設定，⚠️ 早期規劃文件曾寫 NT$90/120，**以本次 NT$50 為準，送審前自行確認** |
| Pro 解除的上限 | 鬧鐘 6→∞、自定鈴聲 5→∞、單段鈴聲 5s→30s、家長錄音 3 分鐘→∞（單一來源 `FeatureLimits`） |
| 購買入口 | 設定 → 家長驗證（ParentalGateView）後 → 「SunnyWalker Pro」→ ProUpgradeView（含 Restore） |

### 🔀 合併步驟（在 Mac 上做，sandbox 無法安全 merge）

> Cowork 的 Linux sandbox 無法刪 `.git/*.lock`、也無 Xcode/xcodegen，**不要在 sandbox merge**。
> 此 merge 有 6 個衝突檔，其中 pbxproj / xcstrings 必須用 Xcode/xcodegen 重生，務必在 Mac 上做。

```bash
cd ~/Documents/SunnyWalker
rm -f .git/index.lock .git/HEAD.lock .git/objects/maintenance.lock   # 清 sandbox 殘留 lock
git checkout main && git status            # 必須乾淨；目前 main 領先 origin 3 個 commit
git merge --no-ff --no-commit feature/pro-iap-lifetime
```

預期 6 個衝突檔，逐檔處理：

| 衝突檔 | 怎麼解 |
|---|---|
| `project.yml` | **兩邊都留**：保留 pro 的 StoreKit/IAP 設定 + main 其他設定；版本改成 **`MARKETING_VERSION: "1.3.20260614"`、`CURRENT_PROJECT_VERSION: 11`** |
| `SunnyWalker.xcodeproj/project.pbxproj` | **別手解**。先 `git checkout --theirs` 取 pro 版，解完 `project.yml` 後跑 `xcodegen generate` 整個重生，再 `git add` |
| `SunnyWalker/Localizable.xcstrings` | 先 `git checkout --theirs`（pro 含全部 `pro_*` key），再用 Xcode build 一次讓字串抽取補回 main 端的 key，確認每個 key 中(zh-Hant)英(en)都齊（verify script 會掃缺漏） |
| `SunnyWalker/Views/Home/HomeView.swift` | **手解**：同時保留 main 的吉卜力改動（`MascotView(scene:)` 等）＋ pro 的 `showingPro` / 設定頁 Pro 列 / `ProUpgradeView` sheet / `StoreService` 注入 |
| `SunnyWalker/Views/Settings/VoiceLibraryView.swift` | **手解**：main 已先併入 pro 的非 IAP 部分（commit 9ce1dfb），衝突多半是「到上限」的付費判斷 → 保留 pro 走 `FeatureLimits` 的版本，別讓 UI 重複 |
| `SunnyWalker/Services/AudioPlayer.swift` | main 已併入 pro 的暫停/續播（9ce1dfb），衝突多半瑣碎 → 確認暫停/續播只留一份即可 |

解完後：

```bash
bash scripts/verify_pro_iap.sh     # 清 lock → xcodegen → build → unit tests → xcstrings/FeatureLimits 掃描
# Xcode → Scheme → Run → Options → StoreKit Configuration 設為 Configuration.storekit（本機測購買）
git commit                          # 保留 merge commit 訊息
```

### App Store「版本說明 / What's New」

#### 繁體中文（zh-Hant）

```
SunnyWalker Pro 來了 ✨

‧ 一次購買、永久解鎖：鬧鐘數量、自定鈴聲數量與長度、爸媽錄音長度，全部無上限
‧ 支援家庭共享，一人購買、全家共用
‧ 購買入口放在「設定」的家長驗證之後，孩子不會誤觸
‧ 感謝老朋友：已經在用 SunnyWalker 的你，更新後直接免費獲得 Pro、全功能無上限 ☀️

基本的叫醒功能永遠免費；Pro 是給需要更多鬧鐘與更長錄音的家庭。
完全離線、零廣告、不收集任何資料。
```

#### English (en)

```
Meet SunnyWalker Pro ✨

• One-time purchase, unlocked forever: unlimited alarms, unlimited voice clips, longer clips, and longer parent recordings — no caps
• Family Sharing supported — buy once, share with the whole family
• The upgrade lives in Settings behind a parental gate, so kids can't tap to buy
• Thank you to our early friends: if you already use SunnyWalker, this update unlocks Pro for you for free ☀️

The core wake-up features stay free forever; Pro is for families who want more.
Fully offline, zero ads, no data collected.
```

### 送審前最終確認（本次更新）

- [ ] merge 完成、`scripts/verify_pro_iap.sh` 全綠（含 xcstrings 雙語、FeatureLimits 唯一來源）
- [ ] `project.yml`：MARKETING_VERSION `1.3.20260614`、CURRENT_PROJECT_VERSION `11` → `xcodegen generate`
- [ ] 真機驗收 IAP：設定 → **家長驗證後**才看得到「SunnyWalker Pro」→ 購買 → 上限解除；Restore 可還原；StoreKit Transaction Manager 測退款後上限回鎖
- [ ] grandfather：用「裝過舊版」的裝置更新 → 應自動為 Pro（免費）；全新安裝 → 應看到付費頁
- [ ] App Store Connect 先建好 IAP（見 `03_todo_fectures/appstoreconnect/20260614_Pro_IAP_appstoreconnect.md`）並**與本版本一起送審**（首個 IAP 必須隨 binary 審核）
- [ ] Age Rating（Made for Kids 6–8）、App Privacy（Data Not Collected）、Privacy Policy URL 沿用
- [ ] Xcode Organizer → Distribute → Upload（build 11）→ ASC「+ Version」1.3.20260614 掛 build 11 + 貼上方 What's New → Submit（IAP 一併勾選送審）

---

## 1.2.20260613 (build 10) — 切段響滿 30s（通知模式）+ 設定頁錄音管理 + 自訂鈴聲操作優化

> 🆓 **本次為免費版更新**。付費解鎖（alarm 數量／錄音長度）的 IAP 不在此版，留待之後另發。
> 來源：`main`（3 項優化）+ 從 `feature/pro-iap-lifetime` **選擇性合併**——只取一般改進
> （AudioPlayer 暫停/續播、VoiceLibraryView 操作優化），**未取**任何付費門檻
> （StoreService / ProUpgradeView / Configuration.storekit / FeatureLimits 付費鎖）。

| 欄位 | 值 |
|---|---|
| 顯示版本 (Marketing Version) | **1.2.20260613**（新功能 → MINOR bump；⚠️ 版本號請自行確認，若視為延伸亦可用 1.1.20260613） |
| Build (CFBundleVersion) | **10**（9 已被 1.1.20260612 佔用） |
| 送審日期 | 2026-06-13 |
| 前次紀錄 | 1.1.20260612 (9) — 溫和提醒模式 |
| 本次重點 | (1) 溫和提醒模式新增 per-alarm「切段響滿 30 秒」開關：開啟後，**關屏／關 App** 也能用秒級錯開的堆疊通知把語音重複響到約 30 秒；**預設關閉＝只響一下**（不堆疊、不再出現一整排通知）。同一鬧鐘的通知用 `threadIdentifier` 收成一組。(2)「錄音管理」回到設定頁第一項（與新增鬧鐘頁同一入口）。(3) 自訂鈴聲試聽：點一下播放／暫停、長按停止；錄到上限自動保留。(4) 移除設定頁 DEBUG probe。中英字串齊備。 |

> ⚠️ Archive 前必跑 `xcodegen generate`。
> ⚠️ 既有「溫和提醒」鬧鐘升級後切段預設＝off → 會從「響約 30s」變「只響一下」；要 30s 請逐顆鬧鐘開「切段」。
> 裝機抽查：設定 ▸ SunnyWalker ▸ 通知內頁要有「Time Sensitive」開關才代表 entitlement 在 binary。

### App Store「版本說明 / What's New」

#### 繁體中文（zh-Hant）

```
這次更新讓叫醒提示更貼心：

‧「溫和提醒」模式新增「切段響滿 30 秒」：開啟後，就算關螢幕或關掉 App，也能把叫醒語音重複響到約 30 秒，更不容易錯過（預設關閉、只響一下）
‧「錄音管理」回到設定頁，隨時整理你的鈴聲
‧ 自訂鈴聲試聽更好操作：點一下播放／暫停、長按停止
‧ 其他小優化，使用更順手

謝謝你陪 SunnyWalker 一起長大 ☀️
```

#### English (en)

```
A warmer, more reliable wake-up nudge:

• Gentle Reminder mode adds "Ring ~30s in segments": when on, the wake-up voice repeats for about 30 seconds even with the screen off or the app closed, so it's harder to miss (off by default — rings just once)
• "Recordings" is back in Settings, so you can tidy up your sounds anytime
• Easier voice-clip preview: tap to play/pause, long-press to stop
• Other small refinements for a smoother experience

Thanks for growing up with SunnyWalker ☀️
```

### 送審前最終確認（本次更新）

- [ ] `project.yml`：MARKETING_VERSION `1.2.20260613`、CURRENT_PROJECT_VERSION `10`
- [ ] `xcodegen generate` 後再 Archive（Any iOS Device / arm64）
- [ ] **確認沒帶進 Pro/IAP 檔**：`StoreService.swift`、`ProUpgradeView.swift`、`Configuration.storekit`（free 版不應有）
- [ ] Xcode Organizer → Distribute → App Store Connect → Upload（build 10）
- [ ] ASC「+ Version」建立 `1.2.20260613`，附 build 10，貼上方 What's New（中／英）
- [ ] Age Rating、App Privacy（Data Not Collected）、Privacy Policy URL 沿用前版
- [ ] Submit for Review（Made for Kids 更新仍需審核）

---

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
