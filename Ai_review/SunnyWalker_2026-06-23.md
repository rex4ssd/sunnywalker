# SunnyWalker — AI Review 2026-06-23（Tue）

> 自動排程產生。版本現況：`MARKETING_VERSION 1.4.20260622` / build 15（1.3 train build 14 已送審含 Pro IAP）。
> App 定位：7 歲小孩用、**100% 離線**語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit、~12.6k LOC Swift。
> Repo 同時含 Python `claude_loop` 4-agent orchestrator（自動每日造 app）。
>
> **這份是「先寫下來給你看」**——除了寫回本檔，沒有改任何 code。你看完勾選要做的，我再動手。

---

## 0. 本次 review 範圍 & 前置狀況

- `Ai_review/` 資料夾**目前是空的**，沒有任何舊 `SunnyWalker_2026-*.md` 可整理 / 刪除 → 本檔是第一份。
- 今天是**週二**，非週六 → 依排程規則**不需**產生 `SunnyWalker_2026-*-weekly.md`。下一個週六（2026-06-27）才會把「未做完項目」彙整成 weekly。
- 已查 Vein lore（532 筆）：i18n「英文模式不可露中文」與報時 CAF 長度雷已記錄在案，本次審查與之對齊。

---

## 1. 優化空間（待你決定再做）

### 1A. 【高】 必修 — iOS app

| # | 位置 | 問題 | 建議 |
|---|---|---|---|
| 1 | `Services/AlarmKitService.swift`（removeAlarm/syncAlarm 的 `try? stop()`/`try? cancel()`）| AlarmKit 取消/停止失敗被**靜默吞掉**，鬧鐘可能卡住一直響。兒童鬧鐘這是真實事故。 | 失敗要 log + fallback（例如改走通知模式停鈴）。 |
| 2 | `Views/Alarm/AlarmListView.swift:285` | `try! ModelContainer(...)`：SwiftData store 損毀 / migration 失敗 → 整個 view crash。 | 確認是否只在 preview；若 production 可達，改 `do/catch` + in-memory fallback。 |

### 1B. 【高】 必修 — i18n：英文模式洩漏中文（逐條 file:line）

模型：`Text("中文")` 字面值本身就是 String Catalog 的 key，**只有當該 key 有 `en` 值時**才會翻譯。下列 key **缺 `en` 值或未進 catalog**，英文模式直接顯示中文：

| 位置 | 內容 | 修法 |
|---|---|---|
| `Views/Settings/VoiceLibraryView.swift:387` | `accessibilityLabel(Text("已選取"/"選取"))`——catalog 有 key 但無 en 值 | 補 en：Selected / Select |
| `Views/Components/MascotView.swift:149` | `.accessibilityLabel(Text("向日葵"))` 未翻譯 | 補 en：Sunflower |
| `Views/Home/HomeView.swift:781` | `Text("最多只能設定 \(maxAlarms) 個鬧鐘…")` 內插→動態 key 不在 catalog → **alert 全中文** | 改用 catalog 內有的 `%lld` 格式 key |
| `Views/Home/HomeView.swift:1063` | `Text("\(recordingGapSeconds) 秒")` → emit `%lld 秒`（catalog 只有 `%@ 秒`，缺）| 補 `%lld 秒` 或統一格式 |
| `Views/Settings/RecordingView.swift:110` | `L("錄音最長 %lld 分鐘…")` 格式 key 不在 catalog → fallback 露中文 | 補該格式 en 值 |
| `Views/Settings/WakeHistoryView.swift:40,50,66,164` | `全部清除` / `匯出紀錄` / `確定清除全部起床紀錄？` / `刪除這筆紀錄` 四個 key 都不在 catalog | 全補 en（家長頁也要乾淨）|

> 已驗證**不是**洩漏、不用改：ParentalGate 的「請大人來幫忙/取消/口令」、`新增鬧鐘`、`Text(verbatim: name)` 群組名、`#Preview` 內中文（不出貨）。`AlarmKitService.swift:76 AlarmButton("我起床了")` 是 `LocalizedStringResource`，跟著**系統語言**而非 app 內切換——這是 AlarmKit 先天限制，記為 known edge 即可。

### 1C. 【中】 CPU / RAM

- **1Hz polling**：`HomeView.swift:73,289` `foregroundAlarmTick` 只要 Home 在前景就**每秒**跑 `checkForegroundAlarm()`。常駐兒童時鐘 = 持續喚醒。建議放寬節奏或讓無近期鬧鐘時 early-return。（註：`Timer.publish().autoconnect()` 存成 `let` + `.onReceive` **不是** retain cycle，SwiftUI 離場會自動拆訂閱；成本在輪詢不在洩漏。）
- **整張花心照常駐記憶體**：`AppSettings.swift:140,367,385` `flowerImage: UIImage?` 在 init 就從硬碟載入並 `@Published` 整個 app 生命週期持有，即使沒選花朵吉祥物。`saveFlowerImage` 也未縮圖。建議：存檔前縮到 ≤512px、首次用到才 lazy load。另確認 6MB `new_icon.png` 只當 asset icon、沒被 `UIImage(named:)` 常駐。
- **UserDefaults `didSet` 寫入抖動**：`AppSettings.swift:152–290` 每個設定 `didSet` 同步寫 UserDefaults；陣列設定（groupNames/groupMascots/…）任一變更就整包重寫。若有綁 slider/drag 會 thrash → debounce。

### 1D. 【中】/【低】 Orchestrator（Python `claude_loop`）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 【高】 | `orchestrator.py:192-198` | subprocess timeout **只在 stdout 迴圈內檢查**；agent 靜默掛住 → `for line in proc.stdout` 永久阻塞、timeout 永不觸發、整條 pipeline 卡死。 | 用 watchdog thread / `threading.Timer` 到期 kill；現成 `_live_status` 每 3s thread 給它 kill 權。 |
| 【高】 | `orchestrator.py:196,211` | `proc.kill()` 只殺 claude 本身，子孫程序（node/MCP/xcodebuild）不在同 process group → 殘留累積吃 RAM/CPU。 | `start_new_session=True` + `os.killpg(...)`；kill 後 `proc.wait()` 收屍。 |
| 【高】 | `issue/...2026-06-13` 已記錄 | `.git/*.lock` 殘留會擋下一個 agent commit，只表現成 opaque FAILED。 | `Agent.run()` 前置清 stale lock（repo 已有 `remove_git_lock.sh`）。 |
| 【中】 | `orchestrator.py:50-63` | token-limit 判定是 log tail 子字串掃描，含 `"429"`/`"credit"`/`"billing"`——agent 讀到含這些字的原始碼/測試輸出就誤觸 4 小時 cooldown，整個 supervisor 停數小時。 | 只掃 orchestrator 自身 error 行；拿掉裸 `429`/`credit`。 |
| 【中】 | `ring.py` append 無鎖 | 手動 `sw next` 與 supervisor 子程序並跑 → baton 交錯損毀。 | `fcntl.flock` 在 `cmd_next/cmd_today` 期間鎖 `ring.lock`。 |
| 【中】 | `supervise.py:298-304` | `consecutive_failures` 把「cooldown / approval gate / 非工作時段」也算 failure，`stop_after` 一設就容易誤觸「需人介入」退出。 | 只算真正 FAILED/timeout/token-pause。 |
| 【低】 | `orchestrator.py:59,67-73` | `_live_status` 每 3s 重讀**整個** log（成長到 MB）→ 浪費 CPU/RAM。 | seek tail N KB。 |

> 多處 `except Exception: pass`（notify/heartbeat/schedule/archive/supervise）建議至少 debug-log，別全吞。orchestrator 整體 heartbeat/ring/cooldown 設計穩健，這些是 robustness 補強。

---

## 2. 各項功能：缺陷 & 未完成

### 2A. 未解 bug / 待真機驗證

1. **背景整夜自動停鈴**（`issue/issue_alarm.md` 4 輪）：架構已限縮為「keep-alive 撐住時保證 ≤10 分鐘」，被 iOS 整夜殺掉時靠系統未公開的 auto-silence。**真機整夜 + 耗電驗證仍待做。**
2. **溫和提醒長音截斷**（`issue/...2026-06-13`）：已用短 CAF + 堆疊 burst 修好並真機驗證。仍 open：(a) 跑 cutoff-probe 找 iOS 真正截斷點（4.6–29s 之間）；(b) ≥30s 錄音要自動裁切 + UI 警告。
3. **無效 SF Symbol** `mic.badge.checkmark`（語音解除 label）→ log `No symbol named`，要換符號。
4. **前景 AlarmRingView ringTimeout 不寫 WakeRecord** → 無回應自動關閉沒記錄，統計低估。補 `"timeout"` record。
5. **貪睡（snooze）完全未實作**（`issue/issue_snooze.md`，原型已全 revert）：卡在需 Xcode 驗證 iOS 26 `AlarmManager.AlarmConfiguration` initializer；§9 有 6 條待真機確認。
6. **strict mode 死碼殘留**：`requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程、「時空信箱」UI。**被點名為 Pro 招牌功能、免後端，優先做。**
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）。
- 睡前床邊故事（搭 BedSideManager）。
- LINE/區網家長設定每日任務 + 氣球/太陽 todo 指示 + 每週完成紀錄 →（LINE 路徑判定 Made-for-Kids 幾乎無法過審，建議放最後/放棄，改 app 內或 CloudKit）。
- 吉卜力視覺二/三波：A5 CoreMotion 視差、A8 自訂字型、B4 互動彩蛋、B5 動態鬧鐘卡、C 吉祥物瞳孔細節。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（解鎖：鬧鐘 6→∞、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值清單尚未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、**多孩子 profile（兩寶以上剛需）**、per-alarm 吉祥物/顏色、床邊故事 Pro 階。

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- **100% 離線、無廣告、無追蹤** → Made-for-Kids 最強賣點，家長安心、過審友善。
- **語音互動「我起床了」**才能關鬧鐘 → 比一般 okay-to-wake 多了互動 / 訓練自理。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著、家長願記錄成長。
- 家長錄音叫醒 + 起床紀錄 → 情感 + 數據雙價值。

### 缺點 / 可補強
- **缺「routine / 多步驟早晨流程」**：競品（Happy Kids Timer、Timer for Kids）核心是「一步步完成早晨/睡前任務 + 視覺計時器」。SunnyWalker 偏單點鬧鐘，建議把「待辦語音提醒」升級成**可視化分步 routine + 計時器**。
- **缺 okay-to-wake 顏色燈號**：競品標配「紅燈睡/綠燈可起床」。可加日夜情境的「可以起床了」綠色信號，零成本高辨識。
- **缺正向肯定語**：Kids AlarmClock 用「卡通英雄 + 每日肯定語」。可加家長/吉祥物每日鼓勵語。
- **無多孩子 profile**：兩寶家庭剛需，且是自然的 Pro 升級理由。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢圖——做出來能撐 Pro 價值感。
- 真機背景停鈴 / 貪睡尚未收尾 → 1 星負評高風險點，上架前務必驗。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（iOS App Store 兒童時間/鬧鐘類）
- **Woohoo Toddler Clock** — 視覺 okay-to-wake，免費 5 條可編輯 routine 起步（freemium routine 數）。
- **Happy Kids Timer: Home Chores** — 早晚 routine + star 獎勵，家長可用 star 換零用錢；主打 ADHD/自閉友善。
- **Timer for Kids – Routines** — 角色 + 視覺計時器、無帳號無廣告、單任務專注。
- **Kids Activity Clock** — 家長視覺化排程。
- **Kids AlarmClock** — 卡通英雄叫醒 + 每日肯定語。

**可借鏡加入**：分步 routine + 視覺計時器、star→實體獎勵動機、okay-to-wake 燈號、每日肯定語。這些都 on-device、與離線定位相容。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

市場背景：非遊戲 app 收入約 8 成來自訂閱，但**兒童 app 訂閱觀感差、退訂客訴多**——專案既定「終身買斷給家長安心」的方向是對的，**不建議轉訂閱**。在此前提下衝量：

1. **守住「免費功能一個都不鎖」**（Lode 教訓：鎖既有功能 = 1 星 + Apple 觀感差）。轉化要靠**新增的高感知價值**，不是設限。
2. **把 Pro 變成「會持續長大的買斷」**：用 §2C 加值（多孩子 profile、起床 streak/月曆、Pro 吉祥物、床邊故事、時空膠囊）逐步免費追加給 Pro 用戶 → 墊高 lifetime 感、不漲價也值得買。
3. **時空膠囊語音當招牌轉化點**：情感價值高、家長「為了珍貴成長紀錄願付費」、免後端。建議列為下一個主推 Pro 亮點。
4. **多孩子 profile = 最自然的付費觸發**：兩寶家庭一定要 → 在新增第 2 個孩子時提示升級。
5. **價格策略**：US$1.99 終身先驗付費意願是穩健起手。若轉化好，可考慮**階梯**：維持 $1.99 base，未來重磅內容（床邊故事庫 / 大量主題）做成**第二個一次性「Pro+ 內容包」**（仍買斷、非訂閱），而非漲 base 價。
6. **轉化時機設計**：在「達到免費上限」「新增第 2 孩子」「想用 >5s 錄一句完整叫醒」「打開時空信箱」這些**高情緒時刻**出現升級頁，比首開硬推有效。
7. **家長信任 = 留存與口碑引擎**：離線/隱私在 App Store 截圖與描述首屏明講，是兒童類最強轉化文案。

> 結論：方向不是「加閘門逼付費」，而是「持續加家長願意買單的情感型亮點（時空膠囊、床邊故事、多孩子、成長統計），把 $1.99 終身做成越用越值」。短期最高 ROI 兩件事：**(a) 時空膠囊語音、(b) 多孩子 profile + 起床 streak/月曆**。

---

## 5. note 整理結果

- `Ai_review/` 原本為空 → 無舊 note 可「做完刪除 / 未做保留」。本檔即起點。
- 本檔內 §1/§2 已是「未做完」彙整；**下個週六（2026-06-27）**會依規則複製成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly），屆時把已做掉的勾除。
- 資料夾大小寫：實際存在的是 `Ai_review/`（大寫 A），排程文中亦寫過 `/ai_review/`。本檔寫入 `Ai_review/`。**若你希望統一成小寫 `ai_review/`，跟我說、我一次改名 + 更新排程路徑。**

---

## 6. 本次進度（2026-06-23）

- [x] Review 專案結構（iOS app + Python orchestrator + KidBrowser 子專案）
- [x] 逐檔 code review：缺陷 / crash 風險 / CPU / RAM（§1A、§1C、§1D）
- [x] i18n 英文模式中文洩漏稽核 → 找到 6 處（§1B，附 file:line）
- [x] 各項功能缺陷 & 未完成彙整（§2）
- [x] 兒童時間小幫手優缺點（§3）
- [x] 商業 / 試用轉收費 / 競品（§4）
- [x] note 整理 + 建立今日報告（本檔）
- [ ] 等你勾選 §1 要動手的項目 → 我再實作（目前**未改任何 code**）

**建議優先序**：①i18n 6 處（上架品質，工小）→ ②AlarmKit `try?` 吞錯 + `try!` ModelContainer（crash/卡鈴風險）→ ③orchestrator subprocess timeout/killpg（自動化穩定性）→ ④時空膠囊 + 多孩子 profile（商業轉化）。
