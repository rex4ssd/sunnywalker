# SunnyWalker — AI Review WEEKLY 2026-06-27（Sat）

> 週六 rolling backlog。彙整 06-23 ~ 06-27 五份 daily 的「未做完」項目，去重後成單一待辦清單。
> 已完成的項目移到 §0「本週已完成」留底（`[x]`），不再列入 open backlog。
> App 定位：7 歲小孩用、100% 離線語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ 12.79k LOC。Repo 同時含 Python `claude_loop` 4-agent orchestrator。
> 原 daily（06-23/24/25/26）已整理刪除（git 可復原：`git checkout 03c2fbe -- Ai_review/`）。**此後以本檔當唯一待辦清單。**
> 純文字、無 emoji（依 commit `f0aad85` 決定）。嚴重度用【高】【中】【低】。

---

## 0. 本週已完成（留底，不再列 open）

- [x] AlarmKit `try?` 靜默吞掉 stop/cancel → `bestEffortStopCancel`：真失敗 log，benign not-found 才靜默（`ec5816f`）
- [x] `AlarmListView:285 try! ModelContainer` → 查證為 preview-only，production 不可達，結案
- [x] i18n Text/catalog 路徑批修 → catalog 現 359 key、0 缺 en、0 空 en（`ec5816f` 起）
- [x] orchestrator subprocess timeout 永不觸發 → `threading.Timer` watchdog（`ec5816f`）
- [x] `proc.kill()` 殺不乾淨子孫 → `start_new_session=True` + `os.killpg(SIGKILL)`（`ec5816f`）
- [x] 寫死字級 → 語意字體，支援 Dynamic Type（`6f49bcd`）
- [x] ConfettiSwiftUI MIT 致謝（in-app 開源致謝畫面）（`07fefeb`）
- [x] `mic.badge.checkmark` 無效符號 → 已換（grep 只剩合法 `mic.badge.plus`）（`6c11c84`）
- [x] alarm-toggle VoiceOver label 強制走 `LocalizedStringKey`（`ddc2fa0`）
- [x] HomeView `foregroundAlarmTick` 1Hz → `every: 2`（`6c11c84`）
- [x] 時鐘每秒 numericText 重繪 → 改「分鐘桶翻面才更新 state」（`6c11c84`）
- [x] 花心照未縮圖、整張常駐記憶體 → `saveFlowerImage` 存檔前 `downscaled(maxDimension:512)`、scale=1（`6c11c84`；檔在 `Services/AppSettings.swift`）
- [x] review 報告 / docs / release note 清除 emoji（App Store 貼上安全）（`cbc16ea` / `f0aad85`）

---

## 1. 還沒做的優化（open backlog）

### 1A. 【中】 i18n — 剩「不走 String Catalog」三類（catalog 本身乾淨，359 key / 0 缺 en）

| 嚴重度 | 位置 | 內容 | 修法 |
|---|---|---|---|
| 【低】| `Intents/StopAlarmIntent.swift:16,17,25,64,65,70` | `title`/`IntentDescription`/`@Parameter(title:)` 中文 `LocalizedStringResource` 無 en → 捷徑 App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge）|
| 【低】| `Views/Settings/WakeHistoryView.swift:210,218,228` | 匯出 `.md`：檔名 `SunnyWalker_起床紀錄_…`、`static methodLabel(_:)->String` 純中文、`build(...)` 模板全中文 | 英文模式輸出英文模板 + 檔名 |

### 1B. 【低】 CPU / RAM（剩省電 nice-to-have）

- 【低】 **兩個 1Hz timer publisher 常駐**：`HomeView.swift` `ClockHeaderView.tick`（:961）+ `unlockTick`（:1025）皆 `every: 1`；clock 重繪已 gate 但 timer 每秒仍喚醒，`unlockTick` 每秒跑 `clearExpiredParentalUnlockIfNeeded()`（在主 body，非開著 sheet）。修：clock 改 `every: 5`、`unlockTick` 放寬 5–10s 或 gate 在 `isTemporarilyUnlocked`。純省電、工小。
- 【低】 **UserDefaults `didSet` 寫入抖動**（未複查綁定對象）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。待抽查確認是否真綁拖曳。

### 1C. 【中】/【低】 Orchestrator（Python）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 【中】| `orchestrator.py:51-55,64` | `TOKEN_LIMIT_PATTERNS` 含裸 `"credit"/"quota"/"billing"/"429"`，掃 log tail → agent 讀到含字原始碼/測試輸出誤觸 4h cooldown | 只掃 orchestrator 自身 error 行，拿掉裸 `429`/`credit` |
| 【中】| `lib/ring.py:133,151,168,188` | 4 個 `append_*` 都 `RING.open("a")` 無鎖；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】| `supervise.py:238,300` | `consecutive_failures` 把 cooldown/approval/window 中斷也 `+=1`，:224 達 `max_failures` 退場 → 易誤觸退出 | 只算真正 FAILED/timeout/token-pause |
| 【低】| `orchestrator.py:71` `_live_status` | `read_text().splitlines()` 讀整個 log（會長到 MB）| seek tail N KB |
| 待查 | `orchestrator.py:86` / `lib/progress_view.py:29` | block 式 `except Exception:`（非 `:pass`）→ 下次抽讀確認是否吞錯 | 抽讀後決定 |

---

## 2. 各項功能：缺陷 & 未完成（open backlog）

### 2A. 未解 bug / 待真機驗證

0. 【高·新 06-28】 **App Store 二度被拒 — Guideline 2.3 Accurate Metadata（審查員找不到 SunnyWalker Pro）。** Submission `0ff0f2b5-…`、Version 1.3.20260615 (14)。根因：Pro 入口刻意藏在「家長閘 3 位數乘法題 + 設定頁最底部」（符合 Made-for-Kids 1.3），審查員卡在乘法閘進不了設定。Pro 是真功能（`StoreService.swift` 279 行等），**不可移除描述**。修法（選項 A，不改 build）：ASC 回信附精確路徑 + 2 截圖（草稿在 `03_todo_fectures/appstoreconnect/app_review_reject_260627_fix.md`，ASC 純文字、勿用反引號/markdown/「×」）。**長期 SOP**：在 ASC「App Review Information → Notes」預先寫死 Pro 路徑 + 測試帳號乘法答法，避免每次送審重踩。**需你本人在 ASC 操作；本週商業第一優先——沒過審其他都先擱。** 另需核對 free-tier 鬧鐘上限數字（本 weekly §2C 寫 6 / reject doc 寫 10，須三方一致避免再踩 2.3）。
1. 【高】 **背景整夜自動停鈴** — 架構限縮「keep-alive ≤10 分鐘」；真機整夜 + 耗電驗證仍待做。1 星負評最高風險，上架前務必驗。（需 Xcode + 真機）
2. 【中】 **前景 `handleAutoStop` 不寫 WakeRecord** — `AlarmRingView.swift:311-326` 只播 `timeout_sad.wav` + `dismiss()`，缺 `insert(WakeRecord(dismissMethod:"timeout"))`（背景路徑 `drainTimeoutRecords` 已補）→ 前景逾時自動關漏記，回應率/準時率分母低估。補一行即一致。**工最小，建議先收。**
3. 【中】 **溫和提醒長音截斷** — 短 CAF + 堆疊 burst 已修並真機驗證；剩 (a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4. 【中】 **貪睡（snooze）完全未實作** — 原型全 revert，`snooze/貪睡` 字串散在 7 檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5. 【低】 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 + 「時空信箱」UI。Pro 招牌、免後端、優先做。
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。對外文案一律不可出現「Ghibli/吉卜力」（`a4b3f27` 已 scrub）。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘＋待辦 10→∞〔免費上限＝10，鬧鐘與待辦共用同一 Alarm 物件，來源 `AppSettings.swift:30`；06-29 釘死，原寫「6」為過時數字〕、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、多孩子 profile、per-alarm 吉祥物/顏色、床邊故事 Pro 階。（groups 已做 → 多孩子 profile 已落地一半，升級成「孩子檔案」工不大、商業價值高。）

---

## 3. 兒童時間小幫手：優缺點摘要

優點（主打）：100% 離線/無廣告/無追蹤、語音「我起床了」互動、手繪水彩 + 吉祥物 + 獎勵、家長錄音 + 起床紀錄、報時/待辦/群組/Dynamic Type/VoiceOver。

可補強（依 ROI）：① okay-to-wake 綠燈（最高 ROI 免費亮點）② 分步 routine + 視覺計時器 ③ picture-reveal 揭圖 + stars 逐顆消失 ④ 集星→吉祥物換裝獎勵經濟 ⑤ ADHD 友善「可移除倒數」開關 ⑥ 起床數據加深（streak/月曆/趨勢）⑦ 真機背景停鈴/貪睡收尾。

---

## 4. 商業 / 變現重點

維持 US$1.99 終身買斷、不轉訂閱。守住「免費功能一個都不鎖」，靠新增高感知價值轉化。

最高 ROI（全 on-device、與離線相容）：
1. **okay-to-wake 綠燈 + 過渡倒數**（近零成本免費亮點，競品幾乎標配）。
2. **時空膠囊語音**（Pro 招牌、免後端、情感轉化）。
3. **groups → 多孩子 profile + 起床 streak/月曆**（最自然付費觸發）。
4. **集星 → 吉祥物換裝/場景獎勵經濟**（留存 + 轉化雙引擎、Pro 觸發點）。
5. **完成音效 + 主題/背景包**（Visual Timer Kids 模式）→ 第二個一次性「Pro+ 內容包」素材。

轉化時機：達免費上限 / 新增第 2 孩子 / 想錄 >5s 完整叫醒 / 打開時空信箱 / 想換吉祥物造型。
價格：US$1.99 base 先驗付費意願（市場帶 US$2.99–8.99）；轉化好 → 不漲 base，改做第二個一次性 Pro+ 內容包。
招牌視覺：學 Time Timer，擁有一個專屬視覺隱喻（水彩日出 / 花瓣綻放）當識別資產。

競品借鏡來源：Woohoo Toddler Clock、Sun to Moon Sleep Clock、Time To Wake Night Light、Sleep Clock、Visual Timer Kids、Time Timer、Happy Kids Timer、Timer for Kids – Routines。

---

## 5. 下週建議起手順序（依 ROI / 工量）

1. 前景 `handleAutoStop` 補 timeout WakeRecord（§2A #2）— 一行，補統計缺口。
2. 真機背景停鈴整夜 + 耗電驗證（§2A #1）— 上架最高風險，需 Xcode/真機。
3. orchestrator robustness：`ring.py` flock + `consecutive_failures` 只算真失敗（§1C）— 避免半夜誤退場。
4. 商業免費亮點：okay-to-wake 綠燈 + 過渡倒數（§4 #1）。
5. Pro 招牌：時空膠囊語音（§4 #2）。
6. 收尾：i18n（StopAlarmIntent + 匯出模板，§1A）+ 兩個 1Hz timer 放寬（§1B）。
