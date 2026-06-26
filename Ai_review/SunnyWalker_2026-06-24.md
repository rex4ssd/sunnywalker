# SunnyWalker — AI Review 2026-06-24（Wed）

> 自動排程產生。延續 `SunnyWalker_2026-06-23.md`。
> App 定位：7 歲小孩用、**100% 離線**語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。
> Repo 同時含 Python `claude_loop` 4-agent orchestrator。
>
> **本檔一樣是「先寫下來給你看」——除了寫回本檔，沒有改任何 code。** 你勾選要做的，我再動手。
> 今天是**週三**，非週六 → 依排程規則**不產生 weekly**。下一個週六（2026-06-27）才把未做完項目存成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`。

---

## 0. 自上次 review（06-23）以來的變化 — 先對帳

好消息：**06-23 點名的 【高】 必修，大多已在 commit `ec5816f` 修掉了**，而且這兩天還長出三個新功能。先把帳對清楚：

### 已修（06-23 → 今天已解）

| 06-23 編號 | 項目 | 狀態 |
|---|---|---|
| §1A #1 | AlarmKit `try?` 靜默吞掉 stop/cancel 失敗 | 改成 `bestEffortStopCancel`：真失敗會 log，benign not-found 才靜默 |
| §1A #2 | `AlarmListView:285 try! ModelContainer` crash 風險 | **查證為 preview-only**（在 `#Preview` 內），production 不可達 → 非缺陷，結案 |
| §1B（大部分）| i18n 英文模式洩漏中文（6 處 Text/catalog）| HomeView 內插改 `String(...)` 對上 `%@` key；catalog 補了 已選取/選取/向日狀/全部清除/匯出紀錄/確定清除…/刪除這筆/鬧鐘上限/錄音最長 %lld 分鐘 |
| §1D 【高】 | orchestrator subprocess timeout 永不觸發 | 改用 `threading.Timer` watchdog，靜默掛住也會到期 kill |
| §1D 【高】 | `proc.kill()` 只殺 claude、子孫殘留 | `start_new_session=True` + `os.killpg(SIGKILL)` 整棵 process group 收掉 |

> 我有逐項 diff 比對：catalog 現在掃描結果是 **357 個 key、0 個中文字面 key 缺 `en`、0 個 `en` 值是空的** → Text() 路徑的洩漏確實清乾淨了。

### 新增功能（06-22～06-23，06-23 review 沒涵蓋到，我這次補審）

- **多人鬧鐘（groups）**：每個群組各自的鬧鐘清單、吉祥物、自訂花心、群組開關。
- **報時（time chime）**：`ChimeSoundComposer` 用 `AVSpeechSynthesizer` 離線 render 成 CAF，連報 N 次。
- **待辦語音提醒（todo）**：`TodoBadgesView` 主頁吉祥物旁冒出家長挑的圖示，小孩點→播語音、長按→確認、寫 `TodoPlayRecord`，家長在「待辦紀錄」頁看「已接收」。

**審查結論：這三個新功能寫得很穩，沒發現結構性缺陷。** 特別點名兩個做對的地方：
- `ChimeSoundComposer.compose(...)` 內部用 semaphore 等 render，**全部呼叫端都正確包在 `Task.detached`**（AlarmEditorView ×2、AlarmScheduler ×1）→ 沒踩到 vein 記過的「AVSpeech/AVAudioSession 不可在 main thread」那條雷。
- 報時有完整 **中/英分支**（`zh-TW` / `en-US`，英文走 "It's seven o'clock…"），英文模式報時不會講中文。
- `TodoBadgesView` 用 **15s** tick（提醒型不需秒級），不是 1Hz，成本可接受。

---

## 1. 還沒做的優化（從 06-23 帶過來 + 本次新發現）

### 1A. 【高】 i18n — 還有一類洩漏沒清：**「非 Text 的純 String 路徑」**

06-23 的修法只蓋到 `Text("中文")` 走 String Catalog 的 key。但有一類字串**根本不經過 catalog**，所以英文模式照樣露中文。這是這次新挖到的、最值得修的一條：

| 位置 | 內容 | 為什麼會漏 | 修法 |
|---|---|---|---|
| `Views/Alarm/WakeHistoryView.swift:218-225` `methodLabel(_:)` | `語音 / 按鈕 / 輔助 / 沒有回應` | `switch` 直接 `return "語音"` 是**純 String**，不是 `Text`，不會自動本地化；起床紀錄列表直接顯示 | 回 catalog key 或包 `L("語音","Voice")` |
| `Views/Alarm/AlarmListView.swift:170` | `.accessibilityLabel(alarm.isEnabled ? "關閉鬧鐘" : "開啟鬧鐘")` | `accessibilityLabel` 收 String literal **不會本地化**（只有 `Text(...)` 會）→ VoiceOver 英文模式講中文 | 包成 `Text(...)` 或 `L(...)` |
| `Intents/StopAlarmIntent.swift:16,17,25` | `title="停止鬧鐘"`、`IntentDescription("關掉…")`、`@Parameter(title:"鬧鐘識別碼")` | `LocalizedStringResource` 跟**系統語言**走、且字面當 key，無 `en` 值就露中文（顯示在「捷徑」App / 系統 intent UI）| 補 en 值；屬 AlarmKit/Intents 先天 known-edge，優先序中 |
| `Views/Alarm/WakeHistoryView.swift:246-262` | 匯出的 `.md` 報告全中文（`# SunnyWalker 起床紀錄` / `## 統計總覽` …）| 匯出內容是手組字串，沒接 i18n | 英文模式匯出英文模板（家長分享給英語家庭時才乾淨）；優先序低 |
| 待**驗證**（可能 false alarm）| `AlarmIOView.swift:25,29` `Section("匯出")` / `ShareLink("分享匯出內容")`、`VoiceLibraryView.swift:157` 空狀態 `還沒有錄音…` | 這些是 `LocalizedStringKey`，**有** en 值就沒事 | 開英文模式跑一次這兩頁，確認有翻到 |

> 一句話總結這次的 i18n：**Text() 那批已清乾淨，剩下的是「String/accessibilityLabel/LocalizedStringResource/匯出模板」這些不走 catalog 的路徑。** 工不大，但 §1A 前兩條（methodLabel、accessibilityLabel）是家長頁/VoiceOver 會直接看到的，建議跟著上一批一起收掉。

### 1B. 【中】 CPU / RAM（06-23 §1C，**尚未動**，仍 open）

- **HomeView 有 3 個 1Hz Timer 常駐**：`foregroundAlarmTick`（:73）、`tick`（:968）、`unlockTick`（:1023）全是 `every: 1`。兒童時鐘長時間擺在前景 = 每秒喚醒 ×3。建議：無近期鬧鐘/未在解鎖流程時 early-return 或放寬節奏（報時/待辦已示範 15s tick 的好做法，可參考）。
- **整張花心照常駐記憶體 + 未縮圖**：`AppSettings.swift:140` init 就 `loadFlowerImageFromDisk()` 並 `@Published` 整個生命週期持有；`saveFlowerImage`（:385-389）直接 `pngData()` 寫檔、**沒縮到 ≤512px**。建議存檔前縮圖 + 首次用到才 lazy load。
- **UserDefaults `didSet` 寫入抖動**（06-23 §1C 第三點）：陣列設定任一變更整包重寫，若綁 slider/drag 會 thrash → debounce。（未複查，沿用 06-23 判斷。）

### 1C. 【中】/【低】 Orchestrator（06-23 §1D 剩下的，**尚未動**，仍 open）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 【中】 | `orchestrator.py:52-55` | token-limit 判定仍含裸 `"429"`/`"credit"`/`"billing"` 子字串；agent 讀到含這些字的原始碼/測試輸出就誤觸 4 小時 cooldown | 只掃 orchestrator 自身 error 行，拿掉裸 `429`/`credit` |
| 【中】 | `lib/ring.py`（append_* 無鎖）| 手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】 | `supervise.py` `consecutive_failures` | 把 cooldown / approval gate / 非工作時段也算 failure，`stop_after` 易誤觸退出 | 只算真正 FAILED/timeout/token-pause |
| 【低】 | `orchestrator.py:71`（`_live_status`）| 每 3s `read_text()` **整個** log（會長到 MB）| seek tail N KB |
| 【低】 | 多處 `except Exception: pass` | 全吞錯難 debug | 至少 debug-log |

---

## 2. 各項功能：缺陷 & 未完成（06-23 §2 帶過來，逐條更新狀態）

### 2A. 未解 bug / 待真機驗證（**全部仍 open**）

1. **背景整夜自動停鈴** — 架構已限縮為「keep-alive 撐住時 ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險點，上架前務必驗。
2. **溫和提醒長音截斷** — 已用短 CAF + 堆疊 burst 修好並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
3. **無效 SF Symbol `mic.badge.checkmark`** — 已定位：`AlarmEditorView.swift:538 Label("啟用口令關閉", systemImage:"mic.badge.checkmark")`，**仍在、未換**。會 log `No symbol named`、圖示不顯示。換成 `mic.badge.plus` 或 `checkmark.circle` 之類。**工最小、建議順手修。**
4. **前景 AlarmRingView ringTimeout 不寫 WakeRecord** — 無回應自動關閉沒記錄，統計低估。補 `"timeout"` record（註：`methodLabel` 已預留 `case "timeout": 沒有回應`，所以寫入端補上就完整）。
5. **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 個檔（SunnyWalkerApp/Alarm/StopAlarmIntent/AlarmRingView/AlarmScheduler/AudioRecorder/AlarmKitService）。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
6. **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO（沿用 06-23）

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 + 「時空信箱」UI。**被點名為 Pro 招牌、免後端、優先做。**
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）。
- 睡前床邊故事（搭 BedSideManager）。
- 吉卜力視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。
  - 注意：06-16 已有 commit `a4b3f27 scrub Ghibli references`（App Review 4.1）。**對外文案/識別字一律不可出現「Ghibli/吉卜力」**，二/三波只做「風格」不掛名。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘 6→∞、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值清單尚未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、**多孩子 profile**、per-alarm 吉祥物/顏色、床邊故事 Pro 階。

> 補充：multi-person **groups** 已經做了 → 「多孩子 profile」其實已落地一半（群組＝人）。可把它升級成正式的「孩子檔案」（頭貼/名字/各自起床統計）當 Pro 觸發點，工不大、商業價值高。

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- **100% 離線、無廣告、無追蹤** → Made-for-Kids 最強賣點，家長安心、過審友善。
- **語音互動「我起床了」才能關鬧鐘** → 比一般 okay-to-wake 多了互動 / 自理訓練。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄 → 情感 + 數據雙價值。
- **報時 + 待辦語音 + 多人群組** 已補上「不只是單點鬧鐘」的縱深。

### 缺點 / 可補強（對齊本次競品掃描，見 §4A）
- **缺「可視化分步 routine + 視覺計時器」**：Woohoo / Happy Kids Timer / Timer for Kids 的核心都是「一步步走完早晨/睡前流程」。SunnyWalker 的「待辦語音提醒」已是雛形 → **升級成分步 routine + 倒數計時器**就直接對打競品核心。
- **缺 okay-to-wake 顏色燈號**：競品標配「紅燈睡/綠燈可起床」。加一個日夜情境的綠色「可以起床了」信號，零成本高辨識，對學齡前特別有效。
- **缺正向肯定語 / dismiss mission**：Kids AlarmClock 用「每日肯定語」、Alarmy 用「mission 才能關鈴」。SunnyWalker 的語音解除已是溫和版 mission，可加家長/吉祥物**每日鼓勵語**（離線、和定位相容）。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢 → 做出來能撐 Pro 價值感。
- 真機背景停鈴 / 貪睡尚未收尾 → 上架前務必驗（見 §2A）。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026 刷新）

| App | 模式 | 可借鏡的點 |
|---|---|---|
| **Woohoo Toddler Clock** | 免費 5 條可編輯 routine 起步、雲端備份要登入 | okay-to-wake 視覺燈號、routine cloning（睡前/午睡/旅行各一套）|
| **Happy Kids Timer: Home Chores** | IAP 解鎖自訂 4 chores/routine | **ADHD/自閉友善開關（可移除倒數）**、**家長命名獎勵 + 設定目標星數 + 集滿印獎狀**、star 動機 |
| **Timer for Kids – Routines** | 無帳號無廣告、單任務專注 | 角色 + 視覺計時器、專注單步 |
| **Kids AlarmClock** | 卡通英雄叫醒 | 每日肯定語 |
| **Alarmy** | 免費 + IAP US$4.99 起 | **「mission 才能關鈴」**（打字/走路/數學）強互動——SunnyWalker 的「我起床了」可往這方向加趣味關卡 |

**可借鏡加入（全部 on-device、與離線定位相容）**：① 分步 routine + 視覺計時器、② okay-to-wake 綠燈、③ 家長命名獎勵 + 集星印獎狀、④ ADHD 友善「移除倒數」開關、⑤ 每日肯定語。①②③ 最划算。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

市場數據支持**維持買斷、不轉訂閱**：家長明確偏好一次性購買（如 Endless Alphabet $8.99 一次買斷被推薦為「不要再多一個月費」的代表），兒童 app 訂閱觀感差、退訂客訴多。專案既定方向是對的。在此前提下衝量：

1. **守住「免費功能一個都不鎖」**（Lode 教訓：鎖既有功能 = 1 星 + Apple 觀感差）。轉化靠**新增高感知價值**，不是設限。
2. **把 Pro 做成「會持續長大的買斷」**：用 §2C 加值逐步免費追加給 Pro 用戶 → 墊高 lifetime 感，不漲價也值得買。
3. **時空膠囊語音 = 招牌轉化點**：情感價值高、家長「為珍貴成長紀錄願付費」、免後端。列為下一個主推 Pro 亮點。
4. **多孩子 profile = 最自然付費觸發**（groups 已做一半）：新增第 2 個孩子時提示升級。
5. **價格策略**：US$1.99 終身先驗付費意願是穩健起手。市場參考帶：兒童工具型一次買斷常見落在 **US$2.99–8.99**。若轉化好，**不漲 base、改做第二個一次性「Pro+ 內容包」**（床邊故事庫 / 主題包，仍買斷非訂閱）。
6. **轉化時機設計**：在「達免費上限」「新增第 2 孩子」「想錄 >5s 完整叫醒」「打開時空信箱」這些**高情緒時刻**彈升級頁，比首開硬推有效。
7. **家長信任 = 留存與口碑引擎**：離線/隱私在 App Store 截圖與描述**首屏**明講，是兒童類最強轉化文案。

> 結論：方向不是「加閘門逼付費」，而是「持續加家長願買單的情感型亮點（時空膠囊、床邊故事、多孩子、成長統計），把 $1.99 終身做成越用越值」。短期最高 ROI：**(a) 時空膠囊語音、(b) 把 groups 升級成多孩子 profile + 起床 streak/月曆、(c) 借競品的 okay-to-wake 綠燈 + 集星印獎狀。**

---

## 5. note 整理結果

- 現存舊檔只有 `Ai_review/SunnyWalker_2026-06-23.md`。**今天非週六，不做刪除/weekly**——依規則 weekly 在週六（06-27）才把「未做完」彙整成 `SunnyWalker_2026-06-27-weekly.md`，屆時把 §0「已修」那批勾除、只留 open 項。
- 本檔 §0 已把 06-23 → 今天的「做完 vs 還沒做」對帳清楚；§1/§2 即「未做完」彙整，可直接當週六 weekly 的素材。
- 資料夾大小寫：實際是 `Ai_review/`（大寫 A），排程文寫過 `/ai_review/`。本檔寫入 `Ai_review/`。要統一成小寫跟我說，一次改名 + 更新排程路徑。

---

## 6. 本次進度（2026-06-24）

- [x] Review 專案結構 + 對帳 06-23 → 今天（git log / diff）
- [x] 驗證 06-23 【高】 必修：AlarmKit 吞錯修 / `try!`查證 preview-only / i18n Text 批修 / orchestrator timeout+killpg修
- [x] 補審 06-22～23 新功能（groups / 報時 chime / 待辦 todo）→ 結構穩、無重大缺陷
- [x] 新發現：i18n「非 Text 純 String 路徑」洩漏（methodLabel / accessibilityLabel / Intent / 匯出模板）
- [x] 複查仍 open 的 CPU/RAM（3×1Hz timer、flowerImage 未縮圖）與 orchestrator 【中】/【低】
- [x] 各項功能缺陷盤點（mic.badge.checkmark 已定位仍在、snooze、背景停鈴…）
- [x] 競品掃描刷新（Woohoo / Happy Kids Timer / Alarmy…）+ 商業/變現
- [x] note 整理 + 建立今日報告（本檔）
- [ ] 等你勾選 §1/§2 要動手的項目 → 我再實作（**本檔未改任何 code**）

**建議優先序**：
1. **i18n §1A 前兩條**（`methodLabel`、`AlarmListView:170` accessibilityLabel）— 家長頁/VoiceOver 直接可見，工小，跟上一批一起收。
2. **`mic.badge.checkmark` 換符號**（§2A #3）— 一行，順手。
3. **`ringTimeout` 補寫 `"timeout"` WakeRecord**（§2A #4）— methodLabel 已預留，補寫入端即完整。
4. **真機背景停鈴整夜驗證**（§2A #1）— 上架品質最高風險，硬指標。
5. 商業：**時空膠囊語音** + **groups→多孩子 profile/起床 streak**（§4B 最高 ROI）。
