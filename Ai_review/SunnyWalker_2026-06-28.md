# SunnyWalker — AI Review 2026-06-28（Sun）

> 自動排程產生。延續 `SunnyWalker_2026-06-27.md` + rolling backlog `SunnyWalker_2026-06-27-weekly.md`。
> App 定位：7 歲小孩用、100% 離線語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ 12.79k LOC。Repo 同時含 Python `claude_loop` 4-agent orchestrator。
> 本檔一樣是「先寫下來給你看」——沒有改任何 app/orchestrator code，純 review。你勾選要做的我再動手。
> 今天是「週日」 → 依排程規則**不產生新 weekly**（weekly 是週六；`06-27-weekly.md` 昨天已建立，仍是唯一 rolling backlog）。舊 note 整理結果見 §5。
> 純文字、無 emoji（依 commit `f0aad85` 決定）。嚴重度用【高】【中】【低】。

---

## 0. 自上次 review（06-27）以來的變化 — 先對帳

`git log` 自 06-27 以來有 **1 個新 commit**：

| commit | 內容 | 性質 |
|---|---|---|
| `e803dca` | Fix App Store Connect Review Issues | 改 `Localizable.xcstrings`（47 處）+ `SunnyWalker.xcscheme` + 新增 App Review 被拒文件。**未碰任何 open 的 app 邏輯/orchestrator code。** |

**結論：06-27 weekly 列的 open backlog 全部仍 open**（逐條 file:line 對現行 code 複查確認，見下）。但出現一件 06-27 之後的**重大新事件**：App Store 二度被拒（見 §0A）——這是目前最高優先級的上架阻擋點，weekly 尚未收錄，本檔補上並已同步進 weekly backlog。

### 0A.【高·新】App Store 二度被拒 — Guideline 2.3 Accurate Metadata（找不到 SunnyWalker Pro）

- Submission ID `0ff0f2b5-…`、Review date **June 27, 2026**、Device iPad Air 11" (M3)、Version **1.3.20260615 (14)**、類型 Bug Fix Submission。
- 審查員在 App 內**找不到 metadata 描述的 SunnyWalker Pro**，要求「證明入口位置」或「移除 Pro 描述」。
- 已查證：**Pro 是完整實作的真功能**（`StoreService.swift` 279 行 StoreKit 2、`ProUpgradeView.swift`、`AppSettings.swift` gating、`HomeView.swift:1352` 入口、`Configuration.storekit` IAP `app.rexcode.sunnywalker.pro.lifetime`）。**不該走「移除描述」**——那會砍掉真功能。
- **根因（重要洞察）**：Pro 入口刻意「安靜」——藏在 **家長閘（3 位數乘法題）+ 設定頁最底部**，符合 Made-for-Kids（Guideline 1.3）「不對兒童推銷」的設計。審查員很可能**卡在乘法家長閘**，沒答對就進不了設定，自然找不到 Pro。
- **修法已就緒（選項 A，不改 build、不改 metadata）**：在 ASC 回覆精確路徑 + 2 張截圖（家長閘乘法題、設定頁 Pro 列含價格）。英文純 ASCII 回信草稿已寫好在 `03_todo_fectures/appstoreconnect/app_review_reject_260627_fix.md`。
- **待你動作（排程環境做不了，需你本人在 ASC 操作）**：
  1. 截 2 張圖（家長閘畫面、設定頁底部 Pro 列）。
  2. 貼回信草稿（注意：ASC Reply 框純文字，**不要用反引號 / markdown / 乘號「×」**，草稿已全改 ASCII，可整段貼）。
- **產品層教訓（這次 review 最大 takeaway）**：「為了 Kids 合規把 Pro 藏到家長閘後面」是對的設計，但它**會反覆引發 2.3 被拒**——審查員找不到 = 每次送審都可能再卡。**長期解**：保留安靜入口的同時，在 ASC 的「App Review Information → Notes」**預先寫死 Pro 的精確路徑 + 測試帳號乘法題答法**，讓往後每次送審審查員都能一次找到，不必每次靠回信解釋。建議列為上架 SOP 固定一條。

---

## 1. 還沒做的優化（複查後仍 open）

> 全部對 `e803dca` 後的現行 code 逐條 file:line 實查，確認仍 open。

### 1A.【低】 i18n — 剩「不走 String Catalog」兩類（catalog 本身乾淨）

| 嚴重度 | 位置 | 內容（實查仍在） | 修法 |
|---|---|---|---|
| 【低】| `Intents/StopAlarmIntent.swift:16,17,25`（含同檔 `DismissAlarmIntent`）| `static title="停止鬧鐘"/"關閉鬧鐘"`、`IntentDescription("關掉…")`、`@Parameter(title:"鬧鐘識別碼")` 仍是裸中文 `LocalizedStringResource`，無 en → 「捷徑」App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge，優先序低）|
| 【低】| `Views/Settings/WakeHistoryView.swift:210,218,220-221,228` | 匯出 `.md`：檔名 `SunnyWalker_起床紀錄_…`（:210）、`static methodLabel(_:)->String` 回 `"語音"/"按鈕"` 純 String（:218-221）、`build(...)` 模板全中文（:228）| 英文模式輸出英文模板 + 檔名；分享給英語家庭才乾淨 |

> 列表顯示用的 `methodLabel`（:121 `LocalizedStringKey`）、`navigationTitle`（:27）、`confirmationDialog`（:65）走 catalog 有 en → 家長頁畫面本身英文模式 OK。只剩「匯出」這條純 String 路徑 +「捷徑 intent」這條 LocalizedStringResource。

### 1B.【低】 CPU / RAM（剩省電 nice-to-have，全部仍 open）

- **兩個 1Hz timer publisher 常駐**（實查仍 `every: 1`）：`HomeView.swift:962` `ClockHeaderView.tick` + `:1025` `unlockTick`。clock 重繪已 gate（分鐘桶翻面才更新 state），但 **timer 本身每秒仍喚醒**；`unlockTick` 落在 HomeView 主 body（`:1400 .onReceive`），每秒跑 `clearExpiredParentalUnlockIfNeeded()`，與有沒有開 sheet 無關。床頭整夜常駐 = 可量到的固定喚醒。修：clock 改 `every: 5`（同樣 gate 分鐘翻面、不影響準確度）、`unlockTick` 放寬 5–10s 或 gate 在 `isTemporarilyUnlocked` 才跑。純省電、工小。
- **UserDefaults `didSet` 寫入抖動**（仍未複查綁定對象）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。待抽查確認是否真綁拖曳互動。

### 1C.【中】/【低】 Orchestrator（Python，全部仍 open，未動）

| 嚴重度 | 位置 | 問題（實查仍在）| 修法 |
|---|---|---|---|
| 【中】| `orchestrator.py:51-55,64` `TOKEN_LIMIT_PATTERNS` | 仍含裸 `"credit"/"quota"/"billing"/"429"`；`:64 any(p in tail …)` 掃 log tail，agent 讀到含這些字的原始碼 / 測試輸出（HTTP 範例、帳務字眼）→ 誤觸 4h cooldown。註：`:654` 自身就有一行含 "quota" 的訊息，更顯示這些字在 log 裡很常見 | 改成只掃 orchestrator 自身包裝的 error 行，或拿掉裸 `429`/`credit` |
| 【中】| `lib/ring.py:133,151,168,188` `append_*` | 4 個 append 都 `RING.open("a")` **無鎖**；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】| `supervise.py:238,300` `consecutive_failures` | `:300`（及 `:238` 的泛 `except`）把「沒完成（cooldown/approval/window 中斷）」也 `+= 1`，`:224` 達 `max_failures` 即退場 → cooldown/approval/非工作時段易誤觸退出 | 只算真正 FAILED/timeout/token-pause；cooldown/approval/off-hours 不計 |
| 【低】| `orchestrator.py:71` `_live_status` | `read_text().splitlines()` 讀**整個** log（會長到 MB；token 偵測那條已 tail，這條沒）| seek tail N KB |
| 待查 | `orchestrator.py:86` / `lib/progress_view.py:29` | block 式 `except Exception:`（非一行 `:pass`）→ 是否吞錯未確認 | 下次抽讀後決定 |

---

## 2. 各項功能：缺陷 & 未完成（逐條複查，全部仍 open）

### 2A. 未解 bug / 待真機驗證

1.【高】 **背景整夜自動停鈴** — 架構限縮「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險，上架前務必驗。（需 Xcode + 真機，排程環境做不了。）
2.【中】 **前景 `handleAutoStop` 不寫 WakeRecord（實查仍漏）。** `AlarmRingView.swift:311-326` 只 `playEffectOnce("timeout_sad.wav")` + 1.6s 後 `dismiss()`，**沒有** `modelContext.insert(WakeRecord(dismissMethod:"timeout"))`；對照同檔成功路徑 `handleWakeUp`（:354,:368 有 insert）。背景路徑已由 `HomeView.drainTimeoutRecords()` 補上 → 只剩「App 開在前景、響到逾時自動關」這一筆漏記，導致回應率/準時率分母低估。**補一行 insert 即與背景一致，工最小，建議先收。**
3.【中】 **溫和提醒長音截斷** — 短 CAF + 堆疊 burst 已修並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4.【中】 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5.【低】 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 +「時空信箱」UI。Pro 招牌、免後端、優先做。
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。對外文案一律不可出現「Ghibli/吉卜力」（`a4b3f27` 已 scrub）。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘 10→∞、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、多孩子 profile、per-alarm 吉祥物/顏色、床邊故事 Pro 階。（groups 已做 → 多孩子 profile 已落地一半，升級成「孩子檔案」工不大、商業價值高。）

> 註：本次 reject doc 寫的免費上限是「鬧鐘 10 / 鈴聲 5 / 5s」，與 weekly §2C 寫的「鬧鐘 6→∞」略有出入——**請確認 free tier 鬧鐘上限到底是 6 還是 10**（metadata 與 reject 回信須一致，否則又踩 2.3）。這條本身就是潛在被拒點，建議一併核對。

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- 100% 離線、無廣告、無追蹤 → Made-for-Kids 最強賣點，家長安心、過審友善。
- 語音互動「我起床了」才能關鬧鐘 → 比一般 okay-to-wake 多了互動 / 自理訓練。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄（含背景無回應 timeout 統計）→ 情感 + 數據雙價值。
- 報時 + 待辦語音 + 多人群組 + Dynamic Type + VoiceOver → 縱深 & 無障礙到位。

### 缺點 / 可補強（依 ROI，沿用 06-27 競品掃描 + 本次刷新）
- **缺 okay-to-wake 顏色燈號**：Woohoo / Sleep Clock（藍=睡、黃=起）/ Time To Wake（綠燈、純視覺無聲）全標配。加「綠色可以起床了」信號近零成本、辨識度最高，對學齡前最有效。**仍是最高 ROI 的免費亮點。**
- **缺分步 routine + 視覺計時器**：升級現有「待辦語音提醒」即可對打競品核心。
- **缺 picture-reveal 視覺倒數 + stars 逐顆消失到天亮**：水彩吉祥物 / star burst 是現成素材。
- **缺獎勵兌換經濟**：集星→吉祥物換裝/換場景，天然 Pro 觸發點。
- **缺 ADHD/自閉友善「可移除倒數」開關**：低成本、擴大可服務族群。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢。
- **真機背景停鈴 / 貪睡尚未收尾**（見 §2A）。
- **【新】Pro 入口對審查員「太隱形」**（見 §0A）：對兒童是優點，對 App Review 是反覆被拒風險 → 需用 ASC Review Notes 預先說明路徑當常態 SOP。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-06-28 刷新）

本次 web 搜尋結果與 06-27 一致，核心競品不變：**Woohoo Toddler Clock**（免費 5 program、雲端備份要登入、自訂顏色/圖片）、**Time To Wake Night Light**（純視覺無聲、綠燈 + 過渡倒數、friend characters）、**Sleep Clock**（藍睡黃起，最精簡色彩語意）。完整借鏡表見 `06-27-weekly.md` §4。

**本次新增觀察一個名字：AlarmMon（怪獸鬧鐘）** — 用「角色任務 / 互動才能關鬧鐘」做 gamified dismiss。與 SunnyWalker「語音說『我起床了』才能關」是同一條情感互動路線 → 佐證互動式 dismiss 是有市場的差異化資產，可再強化（例如吉祥物會「回應」小孩的起床語音）。

**最划算借鏡（依 ROI）**：① okay-to-wake 綠燈 + 過渡倒數（免費亮點首選）② 分步 routine + 視覺計時器 ③ picture-reveal 揭圖 + stars 逐顆消失 ④ 集星→吉祥物換裝獎勵經濟 ⑤ 完成音效 + 主題/背景包（Pro+ 內容包素材）⑥ ADHD 友善可移除倒數 ⑦ 擁有一個招牌視覺隱喻（水彩日出 / 花瓣綻放，學 Time Timer）。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差）。在此前提下衝量，重點不變：守住「免費功能一個都不鎖」，靠新增高感知價值轉化；把 Pro 做成「會持續長大的買斷」；時空膠囊語音當招牌轉化點；groups→多孩子 profile + 起床 streak/月曆當最自然付費觸發；集星→吉祥物換裝獎勵經濟當留存+轉化雙引擎。價格 US$1.99 先驗付費意願（市場帶 US$2.99–8.99），轉化好不漲 base、改做第二個一次性 Pro+ 內容包。

> **本次商業層最關鍵一句**：目前最大的「轉收費」阻擋不是定價或亮點，而是 **App Store 還沒過審**（§0A）。Pro 已完整實作，**先把 2.3 被拒解掉（回信 + 截圖 + ASC Review Notes 寫死路徑）讓 build 過審上架**，才談得上轉化。這是本週商業優先級第一。

---

## 5. note 整理結果（週日，依規則執行）

今天是**週日** → **不產生新 weekly**（weekly 為週六；`06-27-weekly.md` 昨天已建立，仍是唯一 rolling backlog）。舊 note 整理：

1. **已彙整的舊 daily 刪除**：`06-23 / 06-24 / 06-25 / 06-26` 四份已被 `06-27-weekly.md` 完整彙整（且 06-27 報告也已標記刪除，但因 git-tracked 而復現於磁碟）。依排程文「做完的就刪除」**再次刪除**這四份。git 可復原：`git checkout 03c2fbe -- Ai_review/`。
2. **保留**：`06-27-weekly.md`（rolling backlog，唯一待辦清單）、`06-27.md`（含 App Store 被拒原始脈絡，留 1 天當橋接）、本檔 `06-28.md`（今日）。
3. **weekly backlog 已補新項**：把 §0A 的「App Store 2.3 被拒 / Pro 入口太隱形」加進 `06-27-weekly.md` 的 open backlog 最上方（rolling backlog 應反映最新已知 open 項，否則刪 daily 後會遺失此事件）。
4. **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫 `/ai_review/`。本批寫入 `Ai_review/`。要統一成小寫跟我說。

---

## 6. 本次進度（2026-06-28）

- [x] Review 專案結構 + 對帳 06-27→今天（git：1 commit `e803dca`，純 metadata/scheme/文件，未碰 open 項）
- [x] 發現並記錄**重大新事件**：App Store 二度被拒 2.3（找不到 Pro，根因＝家長閘擋住審查員）→ §0A，修法已就緒（選項 A 回信草稿在 repo）
- [x] 逐條 file:line 對現行 code 複查：StopAlarmIntent / WakeHistory 匯出 / handleAutoStop 缺 WakeRecord / 兩個 1Hz timer / orchestrator 4 項——**全部確認仍 open**
- [x] 抓出 free-tier 鬧鐘上限數字不一致（weekly 寫 6、reject doc 寫 10）→ 須核對，本身是潛在 2.3 被拒點
- [x] 競品掃描刷新（Woohoo / Time To Wake / Sleep Clock 不變；新增 AlarmMon gamified dismiss 佐證互動式關鬧鐘路線）
- [x] 兒童時間小幫手優缺點 + 商業/變現更新（§3 / §4），點明本週商業第一優先＝先過審
- [x] note 整理：週日不產 weekly；刪除 06-23~06-26 已彙整 daily（git 可復原）；把被拒事件補進 weekly backlog
- [x] Vein lore 寫回（App Store 2.3 被拒事件 + open 項仍存在的對帳）
- [ ] 等你勾選 §1/§2/§0A 要動手的項目 → 我再實作（本檔未改任何 app/orchestrator code）

**建議優先序（本週）**：
1.【最高·你動手】**解 App Store 2.3 被拒**（§0A）：截 2 圖 + 貼回信草稿 + ASC Review Notes 寫死 Pro 路徑當常態 SOP。**沒過審，其他都先擱著。**
2.【你動手】核對 free-tier 鬧鐘上限（6 vs 10）讓 metadata / 回信 / code 三者一致（§2C 註），避免再踩 2.3。
3.【我可動手·工最小】前景 `handleAutoStop` 補 insert timeout WakeRecord（§2A #2）——一行，補統計缺口。
4.【你動手·硬指標】真機背景停鈴整夜 + 耗電驗證（§2A #1）——上架品質最高風險。
5.【我可動手】orchestrator robustness：`ring.py` flock + `consecutive_failures` 只算真失敗（§1C）——避免半夜誤退場。
6.【我可動手·省電】兩個 1Hz timer 放寬（§1B）+ i18n 收尾（StopAlarmIntent / 匯出模板，§1A）。
7.【商業】okay-to-wake 綠燈（免費亮點）+ 時空膠囊語音（Pro 招牌）+ 集星→吉祥物換裝獎勵經濟（§4）。
