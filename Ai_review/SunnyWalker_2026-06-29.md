# SunnyWalker — AI Review 2026-06-29（Mon）

> 自動排程產生。延續 `SunnyWalker_2026-06-28.md` + rolling backlog `SunnyWalker_2026-06-27-weekly.md`。
> App 定位：7 歲小孩用、100% 離線語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ 12.79k LOC。Repo 同時含 Python `claude_loop` 4-agent orchestrator。
> 本檔一樣是「先寫下來給你看」——沒有改任何 app/orchestrator code，純 review。你勾選要做的我再動手。
> 今天是「週一」 → 依排程規則**不產生新 weekly**（weekly 是週六）。舊 note 整理結果見 §5。
> 純文字、無 emoji（依 commit `f0aad85` 決定）。嚴重度用【高】【中】【低】。

---

## 0. 自上次 review（06-28）以來的變化 — 先對帳

`git log` 自 06-28 以來有 **1 個新 commit**：

| commit | 內容 | 性質 |
|---|---|---|
| `70d6581` | Clean up and update Ai_review directory | 刪除已彙整的 06-23~06-26 四份 daily、新增 06-28.md、weekly +1 行、新增 `store_risk_check_sunnywalker_260628.md`。**純文件/note 整理，未碰任何 app/orchestrator code。** |

**結論：06-28 列的 open backlog 全部仍 open**（本檔已逐條 file:line 對現行 code 複查確認，見 §1/§2）。

### 0A.【已釐清】free-tier 鬧鐘上限：確認是 **10**，不是 6（修掉 06-28 留下的待核對）

06-28 §2C 註記「weekly 寫 6 / reject doc 寫 10，須核對」。本次直接讀 code 釘死答案：

- `Services/AppSettings.swift:28-30`：`static let freeMaxAlarms = 10`，註解明寫「免費版『全部設定』總量上限＝10：鬧鐘與待辦是同一種 Alarm 物件，所以這個數字同時涵蓋（鬧鐘＋待辦）」。
- 即 **free tier 上限 = 10 個 Alarm 物件（鬧鐘＋待辦共用）**，App Store metadata / reject 回信寫的「10」是對的；**weekly §2C 與更早 daily 寫的「鬧鐘 6→∞」是過時數字**。
- **動作**：本次已把 weekly backlog `06-27-weekly.md` §2C 的「6」就地改成「10」並標註來源（`AppSettings.swift:30`），讓 rolling backlog 與 code 對齊，避免 ASC metadata 再因數字不一致踩 Guideline 2.3。**請你確認 App Store 描述頁寫的也是 10**（三方一致：code / metadata / 回信）。

### 0B.【高·延續】App Store 二度被拒 2.3（找不到 Pro）— 仍是本週第一優先，等你在 ASC 操作

延續 06-28 §0A，狀態不變、**尚未送出回覆**（排程環境做不了，需你本人）：
- 回信草稿已就緒：`03_todo_fectures/appstoreconnect/app_review_reject_260627_fix.md`（純 ASCII，可整段貼，勿用反引號 / markdown / 乘號）。
- 根因：Pro 入口刻意藏在「家長閘（3 位數乘法題）＋設定頁最底部」，審查員卡在乘法閘進不了設定 → 找不到 Pro。Pro 是真功能（`StoreService.swift` 279 行 StoreKit 2 等），**不可走「移除描述」**。
- **待你動作**：(1) 截 2 張圖（家長閘乘法題畫面、設定頁底部 Pro 列含價格）；(2) 貼回信草稿；(3) **長期 SOP**：在 ASC「App Review Information → Notes」預先寫死 Pro 精確路徑＋測試帳號乘法答法，讓往後每次送審審查員一次找到，不必每次靠回信。
- 另：`store_risk_check_sunnywalker_260628.md`（昨天 commit 新增）建議併進上架 SOP 一起看。

---

## 1. 還沒做的優化（複查後仍 open）

> 全部對 `70d6581` 後的現行 code 逐條 file:line 實查，確認仍 open。

### 1A.【低】 i18n — 剩「不走 String Catalog」兩類（catalog 本身乾淨）

| 嚴重度 | 位置（本次實查行號） | 內容 | 修法 |
|---|---|---|---|
| 【低】| `Intents/StopAlarmIntent.swift:16,17,25,64,65,70` | `title="停止鬧鐘"/"關閉鬧鐘"`、`IntentDescription("關掉…")`、`@Parameter(title:"鬧鐘識別碼")` 仍是裸中文 `LocalizedStringResource`，無 en → 「捷徑」App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge，優先序低）|
| 【低】| `Views/Settings/WakeHistoryView.swift:210,218,220-221,228` | 匯出 `.md`：檔名 `SunnyWalker_起床紀錄_…`（:210）、`static methodLabel(_:)->String` 回 `"語音"/"按鈕"` 純 String（:218,220-221）、`build(...)` 模板全中文（:228）| 英文模式輸出英文模板＋檔名；分享給英語家庭才乾淨 |

> 畫面顯示用的 `methodLabel`（:121 `LocalizedStringKey`）、`navigationTitle`（:27）、`confirmationDialog`（:65）走 catalog 有 en → 家長頁畫面本身英文模式 OK。只剩「匯出純 String 路徑」＋「捷徑 intent LocalizedStringResource」兩條。

### 1B.【低】 CPU / RAM（剩省電 nice-to-have，全部仍 open）

- **兩個 1Hz timer publisher 常駐**（本次實查仍 `every: 1`）：`HomeView.swift:962` `ClockHeaderView.tick`、`:1025` `unlockTick`。對照已收的 `:65 sceneTick every:60`、`:75 foregroundAlarmTick every:2` → 這兩個是僅存的 1 秒喚醒源。clock 重繪已 gate（分鐘桶翻面才更新 state），但 timer 本身每秒仍喚醒；`unlockTick` 落在 HomeView 主 body（`:1400 .onReceive`→`:1402 clearExpiredParentalUnlockIfNeeded`），每秒跑、與有沒有開 sheet 無關。床頭整夜常駐 = 可量到的固定喚醒。修：clock 改 `every: 5`（同樣 gate 分鐘翻面、不影響準確度）、`unlockTick` 放寬 5–10s 或 gate 在 `isTemporarilyUnlocked` 才跑。純省電、工小。
- **UserDefaults `didSet` 寫入抖動**（仍未複查綁定對象）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。待抽查確認是否真綁拖曳互動。

### 1C.【中】/【低】 Orchestrator（Python，全部仍 open，未動）

| 嚴重度 | 位置（本次實查行號） | 問題 | 修法 |
|---|---|---|---|
| 【中】| `orchestrator/orchestrator.py:51-55,64` `TOKEN_LIMIT_PATTERNS` | 仍含裸 `"credit"/"quota"/"billing"/"429"`；`:64 any(p in tail …)` 掃 log tail `[-4000:]`，agent 讀到含這些字的原始碼／測試輸出（HTTP 範例、帳務字眼）→ 誤觸 4h cooldown。佐證：`:654` 自身就有一行含 "quota" 的訊息，顯示這些字在 log 很常見 | 改成只掃 orchestrator 自身包裝的 error 行，或拿掉裸 `429`/`credit` |
| 【中】| `orchestrator/lib/ring.py:124,138,155…` `append_*` | 各 `append_*` 都直接 append、**無鎖**（grep 無 `flock`/`fcntl`）；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】| `supervise.py:237-238`（達 `:224 max_failures` 退場）| `:238 consecutive_failures += 1` 在泛 `except` 內，把「沒完成（cooldown/approval/window 中斷）」也計入；`:224` 達 `max_failures` 即退場 → cooldown/approval/非工作時段易誤觸退出 | 只算真正 FAILED/timeout/token-pause；cooldown/approval/off-hours 不計 |
| 【低】| `orchestrator/orchestrator.py:71` `_live_status` | `read_text(...).splitlines()` 讀**整個** log（會長到 MB；token 偵測那條 :61 已 tail `[-4000:]`，這條沒）| seek tail N KB |
| 待查 | `orchestrator/orchestrator.py:86` / `lib/progress_view.py:29` | block 式 `except Exception:`（非一行 `:pass`）→ 是否吞錯未確認 | 下次抽讀後決定 |

---

## 2. 各項功能：缺陷 & 未完成（逐條複查，全部仍 open）

### 2A. 未解 bug / 待真機驗證

1.【高】 **背景整夜自動停鈴** — 架構限縮「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險，上架前務必驗。（需 Xcode + 真機，排程環境做不了。）
2.【中】 **前景 `handleAutoStop` 不寫 WakeRecord（本次再讀 :311-327 確認仍漏）。** `AlarmRingView.swift:311-327` 只 `playEffectOnce("timeout_sad.wav")`（:319）+ 1.6s 後 `dismiss()`（:321-325），**沒有** `modelContext.insert(WakeRecord(...))`；對照成功路徑 `handleWakeUp`（:363 建 `WakeRecord`、:370 `insert`）。背景路徑已由 `HomeView.drainTimeoutRecords()` 補上 → 只剩「App 開在前景、響到逾時自動關」這一筆漏記，導致回應率/準時率分母低估。**補一行 `insert(WakeRecord(dismissMethod:"timeout"))` 即與背景一致，工最小，建議先收。**
3.【中】 **溫和提醒長音截斷** — 短 CAF + 堆疊 burst 已修並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4.【中】 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5.【低】 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 +「時空信箱」UI。Pro 招牌、免後端、優先做。
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。對外文案一律不可出現「Ghibli/吉卜力」（`a4b3f27` 已 scrub）。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（**鬧鐘＋待辦 10→∞**〔見 §0A，free 上限是 10〕、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、多孩子 profile、per-alarm 吉祥物/顏色、床邊故事 Pro 階。（groups 已做 → 多孩子 profile 已落地一半，升級成「孩子檔案」工不大、商業價值高。）

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- 100% 離線、無廣告、無追蹤 → Made-for-Kids 最強賣點，家長安心、過審友善。
- 語音互動「我起床了」才能關鬧鐘 → 比一般 okay-to-wake 多了互動 / 自理訓練。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄（含背景無回應 timeout 統計）→ 情感 + 數據雙價值。
- 報時 + 待辦語音 + 多人群組 + Dynamic Type + VoiceOver → 縱深 & 無障礙到位。

### 缺點 / 可補強（依 ROI，沿用競品掃描 + 06-29 刷新）
- **缺 okay-to-wake 顏色燈號**：Woohoo / Sun to Moon（月=睡、日=起）/ Time To Wake（綠燈、純視覺無聲）全標配。加「綠色可以起床了」信號近零成本、辨識度最高，對學齡前最有效。**仍是最高 ROI 的免費亮點。**
- **缺分步 routine + 視覺計時器**：升級現有「待辦語音提醒」即可對打競品核心。
- **缺 picture-reveal 視覺倒數 + stars 逐顆消失到天亮**（Sun to Moon「26 顆星逐顆消失」）：水彩吉祥物 / star burst 是現成素材。
- **缺獎勵兌換經濟**：集星→吉祥物換裝/換場景，天然 Pro 觸發點。
- **缺 ADHD/自閉友善「可移除倒數」開關**：低成本、擴大可服務族群。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢。
- **真機背景停鈴 / 貪睡尚未收尾**（見 §2A）。
- **Pro 入口對審查員「太隱形」**（見 §0B）：對兒童是優點，對 App Review 是反覆被拒風險 → 需用 ASC Review Notes 預先說明路徑當常態 SOP。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-06-29 刷新）

本次 web 搜尋與 06-27/06-28 一致，核心競品不變：**Woohoo Toddler Clock**（免費 5 條可編輯 program、雲端備份要登入、自訂顏色/圖片）、**Time To Wake Night Light**（綠燈純視覺無聲、過渡倒數、friend 角色 Smiley/Elephant、夜燈色與亮度）、**Sun to Moon Sleep Clock**（日/夜模式、**26 顆星逐顆消失的視覺倒數**、獎勵兌換、sleep sounds + nap timer）。另注意 **REMI（urbanhello）是硬體鬧鐘**而非純 app → 佐證「實體 okay-to-wake 鐘」是一塊獨立市場，SunnyWalker 純 app 走離線/隱私差異化是對的。

**最划算借鏡（依 ROI）**：① okay-to-wake 綠燈 + 過渡倒數（免費亮點首選）② 分步 routine + 視覺計時器 ③ picture-reveal 揭圖 + stars 逐顆消失 ④ 集星→吉祥物換裝獎勵經濟 ⑤ 完成音效 + 主題/背景包（Pro+ 內容包素材）⑥ ADHD 友善可移除倒數 ⑦ 擁有一個招牌視覺隱喻（水彩日出 / 花瓣綻放，學 Time Timer）。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差）。在此前提下衝量，重點不變：守住「免費功能一個都不鎖」，靠新增高感知價值轉化；把 Pro 做成「會持續長大的買斷」；時空膠囊語音當招牌轉化點；groups→多孩子 profile + 起床 streak/月曆當最自然付費觸發；集星→吉祥物換裝獎勵經濟當留存+轉化雙引擎。價格 US$1.99 先驗付費意願（市場帶 US$2.99–8.99），轉化好不漲 base、改做第二個一次性 Pro+ 內容包。

> **本週商業優先級第一仍是「先過審」**（§0B）：Pro 已完整實作，最大轉收費阻擋不是定價或亮點，而是 App Store 還沒過 2.3。回信 + 截圖 + ASC Review Notes 寫死路徑讓 build 上架，才談得上轉化。另一條低風險高報酬：**核對 App Store 描述頁的免費上限數字＝10（§0A）**，避免再因 metadata 不一致被拒。

---

## 5. note 整理結果（週一，依規則執行）

今天是**週一** → **不產生新 weekly**（weekly 為週六）。舊 note 整理：

1. **對帳**：磁碟現有 `06-27.md`、`06-27-weekly.md`、`06-28.md`。06-23~06-26 四份已於 `70d6581` 正式刪除（git 可復原：`git checkout 03c2fbe -- Ai_review/`）。
2. **刪除已被取代的橋接 daily**：`06-27.md` 是當初為保留「App Store 被拒原始脈絡」留的 1 天橋接；該脈絡現已完整收進 `06-28.md`（§0A）與 weekly backlog（§2A 第 0 項）→ 依排程文「做完的就刪除」**刪除 `06-27.md`**（git-tracked，可復原）。
3. **保留**：`06-27-weekly.md`（rolling backlog，唯一待辦清單）、`06-28.md`（昨日，含被拒脈絡）、本檔 `06-29.md`（今日）。
4. **就地修正 weekly**：把 `06-27-weekly.md` §2C 過時的「鬧鐘 6→∞」改為「鬧鐘＋待辦 10→∞」並標來源 `AppSettings.swift:30`（見 §0A），讓 rolling backlog 與 code 一致。
5. **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫 `/ai_review/`。本批寫入 `Ai_review/`。要統一成小寫跟我說。

---

## 6. 本次進度（2026-06-29）

- [x] Review 專案結構 + 對帳 06-28→今天（git：1 commit `70d6581`，純 Ai_review/note 整理，未碰 open 項）
- [x] 釐清並釘死 **free-tier 上限＝10**（`AppSettings.swift:30`，鬧鐘＋待辦共用），修掉 06-28 留的「6 vs 10」待核對 → §0A；已就地改正 weekly backlog
- [x] 逐條 file:line 對現行 code 複查：StopAlarmIntent（:16-70）/ WakeHistory 匯出（:210,218,228）/ handleAutoStop 缺 WakeRecord（:311-327 實讀確認）/ 兩個 1Hz timer（:962,1025）/ orchestrator（TOKEN pattern :51-64、ring.py 無 flock、supervise :238、_live_status :71）——**全部確認仍 open**
- [x] 競品掃描刷新（Woohoo / Time To Wake / Sun to Moon 不變；新增觀察 REMI＝硬體鐘，佐證純 app 走離線差異化）
- [x] 兒童時間小幫手優缺點 + 商業/變現更新（§3 / §4），本週商業第一仍＝先過審
- [x] note 整理：週一不產 weekly；刪除橋接 daily `06-27.md`（git 可復原）；就地修正 weekly free-tier 數字
- [x] Vein lore 寫回（free-tier 10 釘死 + open 項對帳）
- [ ] 等你勾選 §0B/§1/§2 要動手的項目 → 我再實作（本檔未改任何 app/orchestrator code）

**建議優先序（本週）**：
1.【最高·你動手】**解 App Store 2.3 被拒**（§0B）：截 2 圖 + 貼回信草稿 + ASC Review Notes 寫死 Pro 路徑當常態 SOP。**沒過審，其他都先擱著。**
2.【你動手·零工】核對 App Store 描述頁免費上限數字＝**10**（§0A），三方一致（code/metadata/回信）。
3.【我可動手·工最小】前景 `handleAutoStop` 補 insert timeout WakeRecord（§2A #2）——一行，補統計缺口。
4.【你動手·硬指標】真機背景停鈴整夜 + 耗電驗證（§2A #1）——上架品質最高風險。
5.【我可動手】orchestrator robustness：`ring.py` flock + `consecutive_failures` 只算真失敗（§1C）——避免半夜誤退場。
6.【我可動手·省電】兩個 1Hz timer 放寬（§1B）+ i18n 收尾（StopAlarmIntent / 匯出模板，§1A）。
7.【商業】okay-to-wake 綠燈（免費亮點）+ 時空膠囊語音（Pro 招牌）+ 集星→吉祥物換裝獎勵經濟（§4）。
