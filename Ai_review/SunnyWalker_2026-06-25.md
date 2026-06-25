# SunnyWalker — AI Review 2026-06-25（Thu）

> 自動排程產生。延續 `SunnyWalker_2026-06-24.md` / `SunnyWalker_2026-06-23.md`。
> App 定位：7 歲小孩用、**100% 離線**語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ **12.75k LOC**。
> Repo 同時含 Python `claude_loop` 4-agent orchestrator。
>
> 🔎 **本檔一樣是「先寫下來給你看」——除了寫回本檔，沒有改任何 code。** 你勾選要做的，我再動手。
> 今天是**週四**，非週六 → 依排程規則**不產生 weekly**。下一個週六（2026-06-27）才把未做完項目存成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`。

---

## 0. 自上次 review（06-24）以來的變化 — 先對帳

`git log` 顯示 06-24 之後只有 **3 個 commit**，全是品質 / 合規補強，**沒有一個碰到 06-24 點名的 open 項**：

| commit | 內容 | 評價 |
|---|---|---|
| `6f49bcd` | a11y：寫死字級 → 語意字體，支援 Dynamic Type（大字不破版）| ✅ 好。兒童 / 長輩家長放大字體不破版，過審友善 |
| `75fc30e` | Home GroupBanner 去掉 pill chrome，貼合水彩風 | ✅ 純視覺，無風險 |
| `07fefeb` | 補 ConfettiSwiftUI MIT 致謝（in-app 開源致謝畫面）| ✅ 授權合規，上架必要，做對了 |

**結論：06-24 列的 open 項全部原封不動仍 open。** 我這次逐條回去用 file:line 複查，順手抓到 **兩個 06-24 寫得不夠精準、需要更正的判斷**（見下），其餘照舊。

### 🔧 對 06-24 的兩條更正（fact-check 後）

1. **`methodLabel` 不是「起床紀錄列表」洩漏，而是「匯出 .md 模板」洩漏。**
   `WakeHistoryView.swift` 其實有**兩個** methodLabel：
   - `:121 methodLabel: LocalizedStringKey`（`case "timeout": "method_timeout"`）→ **列表顯示走這個**（`:166 Text(methodLabel)`），有進 catalog，**英文模式正常翻譯，不洩漏**。
   - `:218 static func methodLabel(_:) -> String`（`case "timeout": "沒有回應"`）→ **只用在匯出 markdown**（`:258 / :267`）。
   → 所以這條的真正性質是 **§1A 的「匯出模板全中文」那一條**，家長頁列表本身乾淨。**優先序下修**（只有家長按「匯出」分享給英語家庭時才看得到）。

2. **`ringTimeout` 不寫 WakeRecord —「背景路徑」其實已修，剩「前景路徑」仍缺。**
   - 背景 auto-stop：`AlarmAutoStopService` → UserDefaults queue → `HomeView.swift:467-482 drainTimeoutRecords()` 會 `insert(WakeRecord(dismissMethod:"timeout"))`，且 `methodLabel` 已有 `"timeout"` 對應 → **背景無回應已會記錄、統計不再低估**。✅
   - 前景路徑：`AlarmRingView.handleAutoStop()`（:310）只播 `timeout_sad.wav` + `dismiss()`，**沒有 `insert(WakeRecord)`**。→ App 開在前景、響到逾時自動關時，**這一筆仍漏記**。屬小缺口，補一行 insert 即完整（與背景路徑一致）。

---

## 1. 還沒做的優化（從 06-24 帶過來，已逐條 file:line 複查仍 open）

### 1A. 🟡 i18n — 不走 String Catalog 的「純 String / 模板」路徑（catalog 本身已乾淨）

> 複查：`Localizable.xcstrings` 共 **357 key、0 個中文 key 缺 en、0 個 en 值為空** → `Text()` catalog 路徑徹底乾淨，這批不用再動。剩下的全是不經 catalog 的路徑：

| 嚴重度 | 位置 | 內容 | 修法 |
|---|---|---|---|
| 🟡（VoiceOver 可見）| `Views/Alarm/AlarmListView.swift:170` | `.accessibilityLabel(alarm.isEnabled ? "關閉鬧鐘" : "開啟鬧鐘")` — String literal 不本地化 | 包 `Text(...)` 或 `L(...)`，補 en |
| 🟢（捷徑/系統 UI）| `Intents/StopAlarmIntent.swift:64` 等 | `title="關閉鬧鐘"` 等 `LocalizedStringResource` 跟系統語言走、字面當 key | 補 en 值（AlarmKit/Intents 先天 edge，優先序中低）|
| 🟢（家長匯出）| `Views/Settings/WakeHistoryView.swift:246-270` | 匯出 `.md` 全中文模板（`# SunnyWalker 起床紀錄` / `## 統計總覽` / `methodLabel` 純 String…）| 英文模式輸出英文模板；分享給英語家庭才乾淨。優先序低 |

> 一句話：**家長頁、App 內畫面（Text 路徑）英文模式已乾淨**；剩 `accessibilityLabel`（VoiceOver 唸中文）+ Intent + 匯出模板三類不走 catalog 的。前者工最小、建議順手收。

### 1B. 🟡 CPU / RAM（仍 open，未動）

- **HomeView 仍有 3 個 1Hz Timer 常駐**：`foregroundAlarmTick`（:73）、`tick`（:960）、`unlockTick`（:1015）全是 `every: 1`。兒童時鐘長擺前景 = 每秒喚醒 ×3。對照 `TodoBadgesView`（:30）已用 **15s** tick 的好做法 → 建議：無近期鬧鐘 / 未在解鎖流程時 early-return，或拉長到 `unlockTick`/`tick` 只在真正需要秒級時才跑。
- **整張花心照常駐記憶體 + 未縮圖**：`AppSettings.swift:140` init 即 `loadFlowerImageFromDisk()` 並 `@Published`（:367）整個生命週期持有；`saveFlowerImage`（:385-389）直接 `pngData()` 寫檔、**沒縮到 ≤512px**。建議存檔前縮圖 + 首次用到才 lazy load。
- **UserDefaults `didSet` 寫入抖動**（沿用 06-23/24 判斷，未複查）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。

### 1C. 🟡/🟢 Orchestrator（Python，仍 open，未動）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 🟡 | `orchestrator.py` token-limit 判定 | 仍含裸 `"429"`/`"credit"`/`"billing"` 子字串；agent 讀到含這些字的原始碼 / 測試輸出 → 誤觸 4 小時 cooldown | 只掃 orchestrator 自身 error 行，拿掉裸 `429`/`credit` |
| 🟡 | `lib/ring.py`（append 無鎖）| 手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 🟡 | `supervise.py consecutive_failures` | 把 cooldown / approval gate / 非工作時段也算 failure，`stop_after` 易誤觸退出 | 只算真正 FAILED/timeout/token-pause |
| 🟢 | `orchestrator.py _live_status` | 每 3s `read_text()` 整個 log（會長到 MB）| seek tail N KB |
| 🟢 | 多處 `except Exception: pass` | 全吞錯難 debug | 至少 debug-log |

> 註：06-23 點名的 orchestrator 🔴（subprocess timeout 永不觸發、`proc.kill()` 殺不乾淨子孫）已於 `ec5816f` 用 watchdog + `killpg` 修掉，本批是剩下的 robustness 補強。

---

## 2. 各項功能：缺陷 & 未完成（逐條更新狀態）

### 2A. 未解 bug / 待真機驗證

1. 🔴 **背景整夜自動停鈴** — 架構限縮為「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險點，上架前務必驗。**（仍 open）**
2. 🟡 **溫和提醒長音截斷** — 已用短 CAF + 堆疊 burst 修好並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
3. 🟡 **無效 SF Symbol `mic.badge.checkmark`** — **複查：仍在** `Views/Settings/AlarmEditorView.swift:538 Label("啟用口令關閉", systemImage:"mic.badge.checkmark")`。會 log `No symbol named`、圖示不顯示。換 `mic.badge.plus` / `checkmark.circle`。**一行、工最小，建議順手修。**
4. 🟢 **前景 ringTimeout 不寫 WakeRecord** — **更正：背景路徑已修**（`drainTimeoutRecords` 已 insert `"timeout"`）；**剩前景 `AlarmRingView.handleAutoStop()`（:310）仍未 insert**。補一行即與背景一致。
5. 🟡 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 個檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
6. 🟢 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 + 「時空信箱」UI。**被點名為 Pro 招牌、免後端、優先做。**
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 吉卜力視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。
  - ⚠️ `a4b3f27` 已 scrub Ghibli references（App Review 4.1）。**對外文案 / 識別字一律不可出現「Ghibli/吉卜力」**，二/三波只做「風格」不掛名。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘 6→∞、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值清單尚未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、**多孩子 profile**、per-alarm 吉祥物/顏色、床邊故事 Pro 階。

> groups（多人鬧鐘）已做 → 「多孩子 profile」其實已落地一半（群組＝人）。升級成正式「孩子檔案」（頭貼/名字/各自起床統計）當 Pro 觸發點，工不大、商業價值高。

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- **100% 離線、無廣告、無追蹤** → Made-for-Kids 最強賣點，家長安心、過審友善。
- **語音互動「我起床了」才能關鬧鐘** → 比一般 okay-to-wake 多了互動 / 自理訓練。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄（含背景無回應的 timeout 統計）→ 情感 + 數據雙價值。
- 報時 + 待辦語音 + 多人群組 + Dynamic Type（新）→ 縱深 & 無障礙到位。

### 缺點 / 可補強（對齊 §4 競品掃描）
- **缺「可視化分步 routine + 視覺計時器」**：競品（Woohoo / Time To Wake / Happy Kids Timer）核心都是「一步步走完早晨/睡前流程 + 倒數」。SunnyWalker 的「待辦語音提醒」是雛形 → **升級成分步 routine + 倒數計時器**就直接對打。
- **缺 okay-to-wake 顏色燈號**：競品標配「紅燈睡 / 綠燈可起床」（REMI、Time To Wake 都主打）。加日夜情境的綠色「可以起床了」信號，零成本高辨識，對學齡前特別有效。
- **缺正向肯定語 / dismiss mission**：可加家長 / 吉祥物每日鼓勵語（離線、和定位相容）。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢 → 做出來能撐 Pro 價值感。
- 真機背景停鈴 / 貪睡尚未收尾 → 上架前務必驗（見 §2A）。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-06-25 刷新；含本次新增）

| App | 模式 | 可借鏡的點 |
|---|---|---|
| **Woohoo Toddler Clock** | 免費 5 條可編輯 routine 起步、雲端備份要登入 | okay-to-wake 視覺燈號、routine cloning（睡前/午睡/旅行各一套）|
| **REMI – OK to Wake**（本次新增）| 硬體 + app，多合一 | **多合一情境**：okay-to-wake 燈 + 夜燈 + **故事播放器** + MP3 播放 → 印證「床邊故事 / 夜燈」是兒童睡眠類高需求；SunnyWalker 床邊故事 Pro 階方向對 |
| **Time To Wake Night Light**（本次新增）| 免費 + IAP | **綠燈 + 轉換倒數計時器**（讓孩子看「還有多久要起床」）→ 視覺燈號 + 過渡計時器標配 |
| **Happy Kids Timer** | IAP 解鎖自訂 chores | ADHD/自閉友善「可移除倒數」開關、家長命名獎勵 + 集星印獎狀 |
| **Timer for Kids – Routines** | 無帳號無廣告 | 角色 + 視覺計時器、專注單步 |
| **Alarmy** | 免費 + IAP US$4.99 起 | 「mission 才能關鈴」強互動——「我起床了」可往趣味關卡加 |

**最划算的借鏡（全 on-device、與離線定位相容）**：① okay-to-wake 綠燈 + 過渡倒數、② 分步 routine + 視覺計時器、③ 家長命名獎勵 + 集星印獎狀。① 幾乎零成本、辨識度最高，**建議列為下一個免費亮點**（衝口碑、墊高 Pro 感）。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差、退訂客訴多；家長偏好一次性購買）。在此前提下衝量：

1. **守住「免費功能一個都不鎖」**（Lode 教訓：鎖既有功能 = 1 星 + Apple 觀感差）。轉化靠**新增高感知價值**，不是設限。
2. **把 Pro 做成「會持續長大的買斷」**：用 §2C 加值逐步免費追加給 Pro 用戶 → 墊高 lifetime 感，不漲價也值得買。
3. **時空膠囊語音 = 招牌轉化點**：情感價值高、免後端，列為下一個主推 Pro 亮點。
4. **多孩子 profile = 最自然付費觸發**（groups 已做一半）：新增第 2 個孩子時提示升級。
5. **價格**：US$1.99 終身先驗付費意願。市場參考帶 US$2.99–8.99。轉化好 → **不漲 base、改做第二個一次性「Pro+ 內容包」**（床邊故事庫 / 主題包，仍買斷）。
6. **轉化時機**：在「達免費上限」「新增第 2 孩子」「想錄 >5s 完整叫醒」「打開時空信箱」這些**高情緒時刻**彈升級頁。
7. **家長信任 = 留存引擎**：離線 / 隱私在 App Store 截圖與描述**首屏**明講，是兒童類最強轉化文案。

> 結論：短期最高 ROI — **(a) okay-to-wake 綠燈 + 過渡倒數（免費亮點、近零成本）、(b) 時空膠囊語音、(c) groups 升級成多孩子 profile + 起床 streak/月曆。**

---

## 5. note 整理結果

- 現存 `Ai_review/`：`SunnyWalker_2026-06-23.md`、`SunnyWalker_2026-06-24.md`，加本檔 `2026-06-25.md`。
- 今天**週四，非週六** → 依排程規則**不刪除舊檔、不產生 weekly**。下個**週六（2026-06-27）**才把「未做完」彙整成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly），屆時把已做掉的（06-24 §0 ✅ 那批 + 本檔 §0 的 3 個 commit + 兩條更正）勾除、只留 open。
- 本檔 §1/§2 即「未做完」彙整，可直接當週六 weekly 素材。
- ⚠️ **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫過 `/ai_review/`。本檔寫入 `Ai_review/`。要統一成小寫跟我說，一次改名 + 更新排程路徑。

---

## 6. 本次進度（2026-06-25）

- [x] Review 專案結構 + 對帳 06-24 → 今天（git log：3 commit，皆品質/合規補強，未碰 open 項）
- [x] 逐條 file:line 複查 06-24 open 項仍在：`mic.badge.checkmark`✓在、`accessibilityLabel:170`✓在、3×1Hz timer✓在、flowerImage 未縮圖✓在
- [x] fact-check 更正兩條：methodLabel（列表已本地化，只剩匯出模板洩漏）、ringTimeout（背景已寫 timeout record，剩前景缺一行）
- [x] catalog 複掃：357 key / 0 缺 en / 0 空 en → Text 路徑徹底乾淨
- [x] 競品掃描刷新（新增 REMI、Time To Wake）+ 商業/變現更新（okay-to-wake 綠燈列為近零成本免費亮點）
- [x] note 整理（週四，不刪除/不 weekly）+ 建立今日報告（本檔）
- [ ] 等你勾選 §1/§2 要動手的項目 → 我再實作（**本檔未改任何 code**）

**建議優先序**：
1. **`mic.badge.checkmark` 換符號**（§2A #3）— 一行，順手。
2. **`AlarmListView:170` accessibilityLabel 包 `Text/L`**（§1A）— VoiceOver 直接可見，工小。
3. **前景 `handleAutoStop` 補 insert timeout WakeRecord**（§2A #4）— 一行，補齊統計缺口。
4. **真機背景停鈴整夜驗證**（§2A #1）— 上架品質最高風險，硬指標。
5. 商業：**okay-to-wake 綠燈（免費亮點）** + **時空膠囊語音** + **groups→多孩子 profile/起床 streak**（§4B 最高 ROI）。
