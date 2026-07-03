# SunnyWalker — AI Review 2026-07-01（Wed）

> 自動排程產生。延續 `SunnyWalker_2026-06-30.md` + rolling backlog `SunnyWalker_2026-06-27-weekly.md`。
> App 定位：7 歲小孩用、100% 離線語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。
> 規模（本次實測）：SunnyWalker app `12786` 行 Swift + KidBrowser 子專案 `314` 行 = 合計 `13100` 行。Repo 同時含 Python `claude_loop` 4-agent orchestrator。
> 本檔一樣是「先寫下來給你看」——**沒有改任何 app/orchestrator code，純 review**。你勾選要做的我再動手。
> 今天是「週三」 → 依排程規則**不產生新 weekly**（weekly 是週六）。舊 note 整理結果見 §5。
> 純文字、無 emoji（依 commit `f0aad85` 決定）。嚴重度用【高】【中】【低】。

---

## 0. 自上次 review（06-30）以來的變化 — 先對帳

`git log` 自 06-30 以來：**0 個新 commit**。最後一個 code commit 仍是 `70d6581`（commit 日期 `2026-06-28 20:24 +0800`，純 Ai_review/note 整理，未碰 app/orchestrator code）。**自 06-28 起到今天，app/orchestrator code 連續第 4 天零變動。**

`git status` 目前（與 06-30 相同，且多了 06-30.md 變成 untracked）：
- `M  Ai_review/SunnyWalker_2026-06-27-weekly.md`（06-29 review 改過 free-tier 數字，**尚未 commit**）
- `D  Ai_review/SunnyWalker_2026-06-27.md`（06-29 review 刪除橋接 daily，**尚未 commit**）
- `?? Ai_review/SunnyWalker_2026-06-29.md`（untracked）
- `?? Ai_review/SunnyWalker_2026-06-30.md`（untracked）

> 🔴 **連續第 4 天提醒：請 commit 一次。** 06-29 / 06-30 兩份 daily 目前是 **untracked**（git 不認得），萬一被「整理刪除」會**無法復原**（不像已 tracked 的 06-27.md 可 `git checkout` 回來）。這也是 §5 我這次「不主動刪 untracked 檔」的原因。

**結論：06-30 列的 open backlog 100% 仍 open。** 本檔已逐條 file:line 對現行 code 複查（見 §1/§2），行號全部對得上。

### 0A.【高·延續】App Store 二度被拒 2.3（找不到 Pro）— 仍是本週第一優先，等你在 ASC 操作

狀態自 06-28 起**不變、尚未送出回覆**（排程環境做不了，需你本人）：
- 回信草稿已就緒：`03_todo_fectures/appstoreconnect/app_review_reject_260627_fix.md`（純 ASCII，可整段貼，勿用反引號 / markdown / 乘號）。
- 根因：Pro 入口刻意藏在「家長閘（3 位數乘法題）＋設定頁最底部」，審查員卡在乘法閘進不了設定 → 找不到 Pro。Pro 是真功能（`StoreService.swift` 等 StoreKit 2），**不可走「移除描述」**。
- **待你動作**：(1) 截 2 張圖（家長閘乘法題畫面、設定頁底部 Pro 列含價格）；(2) 貼回信草稿；(3) **長期 SOP**：在 ASC「App Review Information → Notes」預先寫死 Pro 精確路徑＋測試帳號乘法答法，讓往後每次送審審查員一次找到。
- 併看 `store_risk_check_sunnywalker_260628.md`（最新一次靜態掃描：**P0 0 / P1 0 / P2 2**，兩項都是「寫死大字級」與「GUI 4.1 需跑 app 截圖比對」的 nice-to-check，無阻擋項）。

### 0B.【中·延續·零工】App Store 描述頁免費上限數字＝10（三方一致）

code 端再確認釘死：`Services/AppSettings.swift:30 static let freeMaxAlarms = 10`、`:37 static var maxAlarms: Int { isPro ? .max : freeMaxAlarms }`（鬧鐘＋待辦共用同一 Alarm 物件，合計上限 10）。**仍待你做**：核對 App Store 描述頁／reject 回信寫的也是 10，避免 metadata 數字不一致再踩 Guideline 2.3。

---

## 1. 還沒做的優化（複查後仍 open）

### 1A.【低】 i18n — 剩「不走 String Catalog」兩類（catalog 本身乾淨、359 key / 0 缺 en）

| 嚴重度 | 位置（本次實查行號） | 內容 | 修法 |
|---|---|---|---|
| 【低】| `Intents/StopAlarmIntent.swift:16,17,25,64,65,70` | `title="停止鬧鐘"/"關閉鬧鐘"`、`IntentDescription("關掉…")`、`@Parameter(title:"鬧鐘識別碼")` 仍是裸中文 `LocalizedStringResource`，無 en → 「捷徑」App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge，優先序低）|
| 【低】| `Views/Settings/WakeHistoryView.swift:207,212-225` | 匯出 `.md`：`defaultFilename()`（:207-211）回 `"SunnyWalker_起床紀錄_yyyyMMdd"`；`methodLabel(_:)->String`（:218-225）回 `"語音"/"按鈕"/"輔助"/"沒有回應"` 純 String；模板註解全中文 | 英文模式輸出英文模板＋檔名；分享給英語家庭才乾淨 |

> 本次實查：畫面顯示路徑走 catalog 有 en（OK）；只剩「匯出純 String」＋「捷徑 intent LocalizedStringResource」兩條。**這就是排程文「英文模式中不能有中文」的唯二殘留點，且只在「家長分享匯出檔／捷徑 App」才會被英語使用者看到，不影響小孩主畫面。**

### 1B.【低】 CPU / RAM（剩省電 nice-to-have，全部仍 open）

- **兩個 1Hz timer publisher 常駐**（本次實查仍 `every: 1`）：`HomeView.swift:962` `ClockHeaderView.tick`、`:1025` `unlockTick`。對照 `:75 foregroundAlarmTick` 已是 `every: 2`、`:65 sceneTick` 是 `every: 60`，可見「放寬」是既定做法。clock 重繪已 gate（分鐘桶翻面才更新 state），但 timer 本身每秒仍喚醒；`unlockTick` 每秒跑 `clearExpiredParentalUnlockIfNeeded()`，與有沒有開 sheet 無關。床頭整夜常駐 = 可量到的固定喚醒。修：clock 改 `every: 5`（同樣 gate 分鐘翻面、不影響準確度）、`unlockTick` 放寬 5–10s 或 gate 在 `isTemporarilyUnlocked` 才跑。純省電、工小。
- **UserDefaults `didSet` 寫入抖動**（仍未複查綁定對象）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。待抽查確認是否真綁拖曳互動。

### 1C.【中】/【低】 Orchestrator（Python，全部仍 open，未動）

| 嚴重度 | 位置（本次實查行號） | 問題 | 修法 |
|---|---|---|---|
| 【中】| `orchestrator/orchestrator.py:51-56` `TOKEN_LIMIT_PATTERNS` | 仍含裸 `"credit"/"quota"/"usage limit"/"insufficient_quota"/"billing"/"429"`；掃 log tail，agent 讀到含這些字的原始碼／測試輸出（HTTP 範例、帳務字眼）→ 誤觸 4h cooldown | 改成只掃 orchestrator 自身包裝的 error 行，或拿掉裸 `429`/`credit` |
| 【中】| `orchestrator/lib/ring.py` `append_*`（in_progress/failed/token_paused…）| 各 `append_*` 直接 append、**無鎖**（grep 全檔無 `flock`/`fcntl`）；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】| `supervise.py:224,237-238` | `:238 consecutive_failures += 1` 在 `:237 if consecutive_failures < max_failures` 的泛 `except` 路徑內，把「沒完成（cooldown/approval/window 中斷）」也計入；`:224` 達 `max_failures` 即退場 → cooldown/approval/非工作時段易誤觸退出 | 只算真正 FAILED/timeout/token-pause；cooldown/approval/off-hours 不計 |
| 【低】| `orchestrator/orchestrator.py:71` `_live_status` | `read_text(...).splitlines()` 讀**整個** log（會長到 MB；token 偵測那條已 tail，這條沒）| seek tail N KB |
| 待查 | `orchestrator/orchestrator.py:86` / `lib/progress_view.py:29` | block 式 `except Exception:`（非一行 `:pass`）→ 是否吞錯未確認 | 下次抽讀後決定 |

---

## 2. 各項功能：缺陷 & 未完成（逐條複查，全部仍 open）

### 2A. 未解 bug / 待真機驗證

1.【高】 **背景整夜自動停鈴** — 架構限縮「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險，上架前務必驗。（需 Xcode + 真機，排程環境做不了。）
2.【中】 **前景 `handleAutoStop` 不寫 WakeRecord（本次再讀 `AlarmRingView.swift` 確認仍漏）。** `handleAutoStop()`（≈:311）只 `playEffectOnce("timeout_sad.wav")` + 延遲後 `dismiss()`，**沒有** `modelContext.insert(WakeRecord(...))`；對照成功路徑 `handleWakeUp()`（≈:354-366）才有 `insert(record)`。背景路徑已由 `HomeView.drainTimeoutRecords()` 補上 → 只剩「App 開在前景、響到逾時自動關」這一筆漏記，導致回應率/準時率分母低估。**補一行 `insert(WakeRecord(dismissMethod:"timeout"))` 即與背景一致，工最小，建議先收。**
3.【中】 **溫和提醒長音截斷** — 短 CAF + 堆疊 burst 已修並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4.【中】 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在多檔（`SunnyWalkerApp.swift`、`Models/Alarm.swift`、`Intents/StopAlarmIntent.swift`、`Views/Alarm/AlarmRingView.swift`、`Services/AlarmScheduler.swift`、`Services/AudioRecorder.swift`、`Services/AlarmKitService.swift`）。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5.【低】 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦（與第 4 項殘留重疊，可一起清）。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 +「時空信箱」UI。Pro 招牌、免後端、優先做。
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。對外文案一律不可出現「Ghibli/吉卜力」（`a4b3f27` 已 scrub）。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘＋待辦 10→∞〔free 上限＝10，見 §0B〕、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、多孩子 profile、per-alarm 吉祥物/顏色、床邊故事 Pro 階。（groups 已做 → 多孩子 profile 已落地一半，升級成「孩子檔案」工不大、商業價值高。）

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- 100% 離線、無廣告、無追蹤 → Made-for-Kids 最強賣點，家長安心、過審友善。
- 語音互動「我起床了」才能關鬧鐘 → 比一般 okay-to-wake 多了互動 / 自理訓練（**這是與競品的核心差異化**，見 §4A）。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄（含背景無回應 timeout 統計）→ 情感 + 數據雙價值。
- 報時 + 待辦語音 + 多人群組 + Dynamic Type + VoiceOver → 縱深 & 無障礙到位。

### 缺點 / 可補強（依 ROI，沿用競品掃描 + 07-01 刷新）
- **缺 okay-to-wake 顏色燈號**：Woohoo / Time To Wake / Sun to Moon / Sleep Clock 全標配「紅=睡、綠/黃=起」。07-01 web 搜尋（Mother.ly、Little Peach Sleep 等育兒站）再次印證：「紅停／綠走」是這個品類在家長心中的**通用語言**，2–3 歲就能懂。加「綠色可以起床了」信號近零成本、辨識度最高，對學齡前最有效。**仍是最高 ROI 的免費亮點。**
- **缺分步 routine + 視覺計時器**：Woohoo 主打「一次設定 → bedtime / quiet play / wake / nap 自動切換」。升級現有「待辦語音提醒」即可對打競品核心。
- **缺 picture-reveal 視覺倒數 + stars 逐顆消失到天亮**：水彩吉祥物 / star burst 是現成素材。
- **缺獎勵兌換經濟**：集星→吉祥物換裝/換場景，天然 Pro 觸發點。
- **缺 ADHD/自閉友善「可移除倒數」開關**：低成本、擴大可服務族群。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢。
- **真機背景停鈴 / 貪睡尚未收尾**（見 §2A）。
- **Pro 入口對審查員「太隱形」**（見 §0A）：對兒童是優點，對 App Review 是反覆被拒風險 → 需用 ASC Review Notes 預先說明路徑當常態 SOP。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-07-01 刷新）

本次 web 搜尋核心競品不變：**Woohoo Toddler Clock**（一次設定 → 全天 bedtime/quiet/wake/nap 自動切換、雲端備份要登入、自訂顏色/圖片）、**Time To Wake Night Light**（綠燈純視覺無聲、過渡倒數、可換朋友造型如大象）、**Sun to Moon Sleep Clock**（日/夜模式、26 顆星逐顆消失的視覺倒數、獎勵兌換、sleep sounds + nap timer）、**Sleep Clock**（藍=睡/黃=起雙色光）。**REMI（urbanhello）是硬體鬧鐘 + 配套 app**（含 nightlight / story player / baby monitor / 對講機 / MP3），佐證「實體 okay-to-wake 鐘」是獨立市場；SunnyWalker 純 app 走離線/隱私 + **語音互動自理**差異化是對的。

> 結論未變：競品全是「被動視覺燈號」；SunnyWalker 唯一有「主動語音互動才能關鈴」的自理訓練。**借鏡競品的視覺燈號（補短板），守住語音互動（顧長板），是最穩的路線。**

**最划算借鏡（依 ROI）**：① okay-to-wake 綠燈 + 過渡倒數（免費亮點首選）② 分步 routine + 視覺計時器（學 Woohoo 全天時段切換）③ picture-reveal 揭圖 + stars 逐顆消失 ④ 集星→吉祥物換裝獎勵經濟 ⑤ 完成音效 + 主題/背景包（Pro+ 內容包素材）⑥ ADHD 友善可移除倒數 ⑦ 擁有一個招牌視覺隱喻（水彩日出 / 花瓣綻放，學 Time Timer）。**新觀察（07-01）**：REMI 把「nightlight + story player + 對講機」綑在一個 app 賣硬體；SunnyWalker 不做硬體，但「家長錄音叫醒」其實已是 REMI「對講機/story」情感賣點的純 app 版——值得在文案上把這點講清楚，當差異化亮點主打。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差）。在此前提下衝量，重點不變：守住「免費功能一個都不鎖」，靠新增高感知價值轉化；把 Pro 做成「會持續長大的買斷」；時空膠囊語音當招牌轉化點；groups→多孩子 profile + 起床 streak/月曆當最自然付費觸發；集星→吉祥物換裝獎勵經濟當留存+轉化雙引擎。價格 US$1.99 先驗付費意願（市場帶 US$2.99–8.99），轉化好不漲 base、改做第二個一次性 Pro+ 內容包。

轉化時機（沿用）：達免費上限 10 / 新增第 2 孩子 / 想錄 >5s 完整叫醒 / 打開時空信箱 / 想換吉祥物造型。

> **本週商業優先級第一仍是「先過審」**（§0A）：Pro 已完整實作，最大轉收費阻擋不是定價或亮點，而是 App Store 還沒過 2.3。回信 + 截圖 + ASC Review Notes 寫死路徑讓 build 上架，才談得上轉化。第二低風險高報酬：**核對 App Store 描述頁的免費上限數字＝10（§0B）**。

---

## 5. note 整理結果（週三，依規則執行）

今天是**週三** → **不產生新 weekly**（weekly 為週六）。舊 note 整理：

1. **對帳**：磁碟現有 `06-27-weekly.md`（rolling backlog）、`06-28.md`、`06-29.md`、`06-30.md`，本檔新增 `07-01.md`。`06-27.md` 已於 06-29 review 刪除（tracked，可 `git checkout 03c2fbe -- Ai_review/` 復原）。
2. **「做完的就刪除」**：自 06-28 起 **0 個新 commit**，沒有任何 backlog 項目被完成 → **本次無可刪除的「已完成」daily**。
3. **不主動刪 untracked 檔（安全考量）**：`06-29.md` / `06-30.md` 目前是 **untracked**，一旦刪除無法用 git 復原。在你尚未 commit 前，這次**全部保留**，不冒「刪了拿不回」的險。weekly（唯一待辦清單）、`06-28.md`（被拒原始 submission/root-cause 證據，過審前留底）也保留。
4. **下一個週六（2026-07-04）weekly 計畫**：屆時把 06-28~07-03 的 daily 去重收進新的 `SunnyWalker_2026-07-04-weekly.md`，舊 daily 再清。**前提是你先把現有 untracked daily commit**，weekly roll-up 才安全。
5. **🔴 待你動作（連續第 4 天）**：`git add Ai_review/ && git commit`，讓 note 與 git 同步、且讓往後的「整理刪除」可復原。
6. **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫 `/ai_review/`。本批一樣寫入 `Ai_review/`。要統一成小寫跟我說。

---

## 6. 本次進度（2026-07-01）

- [x] Review 專案結構 + 對帳 06-30→今天（git：**0 新 commit**，連續第 4 天 code 零變動；最後 code commit 仍 `70d6581`@06-28）
- [x] LOC 釐清：SunnyWalker app 12786 行 + KidBrowser 314 行 = 13100 行（06-30 報告的 12786 是 app-only，數字本身正確）
- [x] 逐條 file:line 對現行 code 複查，**全部確認仍 open**：
  - `AppSettings.swift:30` freeMaxAlarms=10、`:37` maxAlarms（再確認）
  - `StopAlarmIntent.swift:16-70` 裸中文 / `WakeHistoryView.swift:207,218-225` 匯出純中文（i18n 唯二殘留＝英文模式殘中文唯二點）
  - `HomeView.swift:962,1025` 兩個 1Hz timer（對照 `:75` 已 every:2、`:65` every:60）
  - `AlarmRingView.swift` handleAutoStop(≈:311) 缺 WakeRecord（handleWakeUp ≈:354-366 才 insert）
  - orchestrator：`orchestrator.py:51-56` TOKEN pattern 含裸 429/quota、`ring.py` 全檔無 flock、`supervise.py:224/237-238` consecutive_failures 誤計
  - snooze/貪睡 殘留多檔（grep 確認）
- [x] store_risk_check 最新掃描複核：P0 0 / P1 0 / P2 2（無阻擋項）
- [x] 競品掃描刷新（Woohoo/Time To Wake/Sun to Moon/Sleep Clock/REMI；新觀察：REMI 把 nightlight+story+對講機綑 app 賣硬體 → SunnyWalker「家長錄音叫醒」可當純 app 版情感賣點主打）
- [x] 兒童時間小幫手優缺點 + 商業/變現更新（§3 / §4），本週商業第一仍＝先過審
- [x] note 整理：週三不產 weekly；0 新 commit → 無「已完成」可刪；untracked daily 為安全全保留；規劃 07-04 weekly roll-up
- [x] Vein lore 寫回（07-01 排程 review 對帳結果）
- [ ] 等你勾選 §0A/§1/§2 要動手的項目 → 我再實作（本檔未改任何 app/orchestrator code）

**建議優先序（本週，與 06-30 一致，因 code 零變動）**：
1.【最高·你動手】**解 App Store 2.3 被拒**（§0A）：截 2 圖 + 貼回信草稿 + ASC Review Notes 寫死 Pro 路徑當常態 SOP。**沒過審，其他都先擱著。**
2.【你動手·零工】核對 App Store 描述頁免費上限數字＝**10**（§0B），三方一致（code/metadata/回信）。
3.【你動手·SOP】`git commit` 現有 untracked Ai_review daily（§5.5），讓往後整理可復原。
4.【我可動手·工最小】前景 `handleAutoStop` 補 insert timeout WakeRecord（§2A #2）——一行，補統計缺口。
5.【你動手·硬指標】真機背景停鈴整夜 + 耗電驗證（§2A #1）——上架品質最高風險。
6.【我可動手】orchestrator robustness：`ring.py` flock + `consecutive_failures` 只算真失敗（§1C）——避免半夜誤退場。
7.【我可動手·省電】兩個 1Hz timer 放寬（§1B）+ i18n 收尾（StopAlarmIntent / 匯出模板，§1A，「英文模式中不能有中文」唯二殘留）。
8.【商業】okay-to-wake 綠燈（免費亮點）+ 時空膠囊語音（Pro 招牌）+ 集星→吉祥物換裝獎勵經濟（§4）。
