# SunnyWalker — AI Review 2026-06-27（Sat）

> 自動排程產生。延續 `SunnyWalker_2026-06-26.md` / `06-25.md` / `06-24.md` / `06-23.md`。
> App 定位：7 歲小孩用、100% 離線語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ 12.79k LOC。
> Repo 同時含 Python `claude_loop` 4-agent orchestrator。
>
> 本檔一樣是「先寫下來給你看」——除了寫回本檔、產生 weekly、整理舊 note，沒有改任何 app/orchestrator code。你勾選要做的，我再動手。
> 今天是「週六」 → 依排程規則：(1) 把未做完項目彙整成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly）；(2) 把已做掉的勾除、整理舊 daily note。處理結果見 §5。
> 本批報告依 06-26 commit `f0aad85` 的決定「review report 不放 emoji」撰寫，全程純文字 + 文字嚴重度標記。

---

## 0. 自上次 review（06-26）以來的變化 — 先對帳

`git log` 顯示 06-26 之後有 3 個新 commit，全是「文件 / 報告」類，沒有一個碰到 open 的 app/orchestrator code：

| commit | 內容 | 性質 |
|---|---|---|
| `f0aad85` | docs(ai-review)：把 review 報告的 emoji 拿掉、嚴重度圓點改文字 | 純文件，App Store 貼上安全 |
| `cbc16ea` | docs：清掉 docs + release note 全部 emoji/icon | 純文件 |
| `03c2fbe` | 新增 AI 審查記錄文件（把 06-23～06-26 daily 納版控）| 純文件 |

**結論：06-26 列的 open 項全部原封不動仍 open。** 我這次沒有只抄上一份，而是逐條回去用 file:line 對現行 code 複查（見下），順手修正/確認了幾條判斷。

### 本次 file:line 複查 — 已修 vs 仍 open（對現行 code 實查）

已修確認（不再列入 backlog）：

1. **`mic.badge.checkmark` 無效符號** — 確認已換。全專案 grep `mic.badge` 只剩 `RingtonePickerSheet.swift:201` 的 `mic.badge.plus`（合法符號）。
2. **HomeView `foregroundAlarmTick` 1Hz** — 確認已放寬為 `every: 2`（`HomeView.swift:75`）。
3. **時鐘每秒重繪耗電** — 確認已收。`ClockHeaderView`（:961）的 1Hz timer 仍在，但 `.onReceive(tick)`（:982）改成「只在分鐘桶 `Int(now/60)` 翻面才更新 state」，省掉每秒 numericText 轉場重繪。分鐘照樣準時翻。
4. **花心照未縮圖、整張常駐記憶體** — 確認已修，且修正 06-26 的路徑誤植：函式在 **`Services/AppSettings.swift`**（非 Models/）。`saveFlowerImage`（:390）存檔前呼叫 `downscaled(_:maxDimension:)`（:400），縮到 `flowerImageMaxDimension`（512px）、`format.scale=1`（避免 @3x 把記憶體膨脹回去）。
5. **String Catalog（Text 路徑）i18n** — 確認乾淨。`Localizable.xcstrings` 現 **359 key（較 06-25 的 357 多 2）、0 個中文字面 key 缺 en、0 個 en 值為空** → App 內畫面英文模式不洩漏中文。

仍 open 確認（逐條 file:line 實查，往下 §1/§2 詳列）：前景 `handleAutoStop` 仍缺 timeout WakeRecord insert、StopAlarmIntent 6 處中文無 en、WakeHistory 匯出模板全中文、orchestrator 4 項（token pattern / ring flock / consecutive_failures / live_status 全讀）。

### 對 06-26 的一條更正（fact-check 後）

- **`unlockTick` 不是「只綁開著的設定 sheet」。** 06-26 寫「unlockTick 被綁在開著的設定 sheet、驅動 mm:ss 倒數，屬合理常駐」。實查 `HomeView.swift:1400` 的 `.onReceive(unlockTick)` 落在 **HomeView 主 body**（sheet 宣告在其後 :1403–1409），代表只要 Home 在前景，這個 1Hz timer 每秒都會跑 `unlockNow = now` + `clearExpiredParentalUnlockIfNeeded()`，**與有沒有開 sheet 無關**。家長解鎖到期是「分鐘級」需求，不需秒級 → 可放寬到 5–10s 或 gate 在 `isTemporarilyUnlocked` 才跑。**重新歸類為 §1B 的低度 open 項**（非缺陷，省電 nice-to-have）。

---

## 1. 還沒做的優化（複查後仍 open）

### 1A. 【中】 i18n — 剩「不走 String Catalog」的三類（catalog 本身已乾淨）

| 嚴重度 | 位置 | 內容 | 修法 |
|---|---|---|---|
| 【低】（VoiceOver）| 確認 `AlarmListView` 的 toggle label 已包 `Text(...)`（06-25 commit `ddc2fa0`）| —（此條已收，僅記錄）| 無需動 |
| 【低】（捷徑/系統 UI）| `Intents/StopAlarmIntent.swift:16,17,25,64,65,70` | `title="停止鬧鐘"/"關閉鬧鐘"`、`IntentDescription("關掉…")`、`@Parameter(title:"鬧鐘識別碼")` 是 `LocalizedStringResource`，無 en 值 → 在「捷徑」App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge，優先序中低）|
| 【低】（家長匯出）| `Views/Settings/WakeHistoryView.swift:210,218,228` | 匯出 `.md`：檔名 `SunnyWalker_起床紀錄_…`（:210）、`static methodLabel(_:) -> String` 回 `"語音"/"按鈕"` 純 String（:218）、`build(...)` 模板全中文（:228） | 英文模式輸出英文模板 + 檔名；分享給英語家庭才乾淨。優先序低 |

> 註：列表顯示用的 `methodLabel`（:121, `LocalizedStringKey`）已乾淨，`navigationTitle("起床紀錄")`（:27）/ `confirmationDialog`（:65）走 catalog 有 en → 家長頁畫面本身英文模式 OK。只剩「匯出」這條純 String 路徑。

### 1B. 【中】/【低】 CPU / RAM

- **三大耗電源兩個已收**（`foregroundAlarmTick` 2s、clock 分鐘翻面才重繪）、花心照已縮 512px。這批主要收尾。
- **【低】兩個 1Hz timer publisher 仍常駐**（本次更正）：`ClockHeaderView.tick`（:961）與 `unlockTick`（:1025）都是 `every: 1`。clock 的「重繪」雖已 gate，但 **timer 本身每秒仍喚醒**；`unlockTick` 每秒還跑 `clearExpiredParentalUnlockIfNeeded()`。床頭整夜常駐時是可量到的固定喚醒。修法：clock 改 `every: 5`（同樣 gate 分鐘翻面、不影響準確度）、`unlockTick` 放寬到 5–10s 或 gate 在 `isTemporarilyUnlocked`。工小、純省電。
- **【低】UserDefaults `didSet` 寫入抖動**（沿用 06-23/24 判斷，仍未複查綁定對象）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。仍掛 open，待下次抽查確認是否真綁拖曳互動。

### 1C. 【中】/【低】 Orchestrator（Python，仍 open，未動）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 【中】 | `orchestrator.py:51-55,64` `TOKEN_LIMIT_PATTERNS` | 仍含裸 `"credit"`/`"quota"`/`"billing"`/`"429"` 子字串；`:64 any(p in tail …)` 掃 log tail `[-4000:]`，agent 讀到含這些字的原始碼 / 測試輸出（HTTP 範例、帳務字眼）→ 誤觸 4h cooldown | 改成只掃 orchestrator 自身包裝的 error 行，或拿掉裸 `429`/`credit` |
| 【中】 | `lib/ring.py:133,151,168,188` `append_*` | 4 個 append 都 `RING.open("a")` append **無鎖**；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 【中】 | `supervise.py:238,300` `consecutive_failures` | `:300` 把「沒完成（cooldown / approval / window 中斷）」也 `+= 1`，`:224` 達 `max_failures` 即退場 → cooldown/approval/非工作時段易誤觸退出 | 只算真正 FAILED/timeout/token-pause；cooldown/approval/off-hours 不計 |
| 【低】 | `orchestrator.py:71` `_live_status` 區 | `:71 read_text(...).splitlines()` 讀**整個** log（會長到 MB；註：token 偵測那條 :61 已 tail，這條沒）| seek tail N KB |

> 已修不再列：06-23 點名的 orchestrator 【高】（subprocess timeout 永不觸發、`proc.kill()` 殺不乾淨子孫）已於 `ec5816f` 用 watchdog + `killpg` 修掉。
> 本次另觀察到 `orchestrator.py:86` / `lib/progress_view.py:29` 兩處 block 式 `except Exception:`（非 `: pass` 一行式）——可能有 log，不確定是否吞錯，**下次抽讀確認**，暫不列為缺陷。

---

## 2. 各項功能：缺陷 & 未完成（逐條更新狀態）

### 2A. 未解 bug / 待真機驗證

1. 【高】 **背景整夜自動停鈴** — 架構限縮為「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險點，上架前務必驗。（仍 open，需 Xcode + 真機，排程環境做不了。）
2. 【中】 **前景 `handleAutoStop` 不寫 WakeRecord（一行缺口，本次再確認仍 open）。** `AlarmRingView.swift:311-326` 只 `playEffectOnce("timeout_sad.wav")` + 1.6s 後 `dismiss()`，**沒有** `modelContext.insert(WakeRecord(dismissMethod:"timeout"))`；對照同檔成功路徑（:363 `WakeRecord(...)`）有 insert。背景路徑已由 `HomeView.drainTimeoutRecords()` 補上 → 只剩「App 開在前景、響到逾時自動關」這一筆漏記，導致回應率/準時率分母低估。補一行 insert 即與背景一致。工最小、建議順手收。
3. 【中】 **溫和提醒長音截斷** — 已用短 CAF + 堆疊 burst 修好並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4. 【中】 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 個檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5. 【低】 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 + 「時空信箱」UI。被點名為 Pro 招牌、免後端、優先做。
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。
  - `a4b3f27` 已 scrub Ghibli references（App Review 4.1）。對外文案 / 識別字一律不可出現「Ghibli/吉卜力」，二/三波只做「風格」不掛名。

### 2C. 已規劃未做的 Pro 加值（定價已鎖 US$1.99 終身買斷）

Pro base 已出貨（鬧鐘 6→∞、鈴聲庫 5→∞、單則 5s→30s、家長錄音 180s→∞）。**加值清單尚未做**：Pro 專屬吉祥物/場景、替換 app icon、起床紀錄進階（streak/月曆/統計圖）、多孩子 profile、per-alarm 吉祥物/顏色、床邊故事 Pro 階。

> groups（多人鬧鐘）已做 → 「多孩子 profile」其實已落地一半（群組＝人）。升級成正式「孩子檔案」（頭貼/名字/各自起床統計）當 Pro 觸發點，工不大、商業價值高。

---

## 3. 兒童時間小幫手角度：優缺點

### 優點（保持 & 主打）
- **100% 離線、無廣告、無追蹤** → Made-for-Kids 最強賣點，家長安心、過審友善。
- **語音互動「我起床了」才能關鬧鐘** → 比一般 okay-to-wake 多了互動 / 自理訓練。
- 手繪水彩 + 吉祥物 + 獎勵（star burst / confetti）→ 情感黏著。
- 家長錄音叫醒 + 起床紀錄（含背景無回應的 timeout 統計）→ 情感 + 數據雙價值。
- 報時 + 待辦語音 + 多人群組 + Dynamic Type + VoiceOver → 縱深 & 無障礙到位。

### 缺點 / 可補強（對齊 §4 競品掃描）
- **缺 okay-to-wake 顏色燈號**：競品幾乎標配「紅/藍燈睡、綠/黃燈可起床」（Woohoo、Sleep Clock、Time To Wake）。加日夜情境的綠色「可以起床了」信號，近零成本、辨識度最高，對學齡前特別有效。**仍是最高 ROI 的免費亮點。**
- **缺「可視化分步 routine + 視覺計時器」**：競品核心都是「一步步走完早晨/睡前流程 + 倒數」。SunnyWalker 的「待辦語音提醒」是雛形 → 升級成分步 routine + 倒數計時器就直接對打。
- **缺「picture-reveal 視覺倒數」**：Visual Timer Kids 主打「圖片隨倒數逐漸顯現 + 完成音效」。SunnyWalker 水彩吉祥物天生適合做揭圖動畫，幾乎是現成素材再利用。
- **缺「stars 逐顆消失到天亮」視覺倒數**（本次新觀察，見 §4）：Sun to Moon 用星星逐顆消失代表「離天亮還有多久」。可直接接 SunnyWalker 現有 star burst / 水彩。
- **缺獎勵兌換經濟**：Sun to Moon 用「集獎勵→換角色禮物」做長期動機。SunnyWalker 已有 star burst，可把「集星」接到吉祥物換裝/換場景，天然 Pro 觸發點。
- **缺 ADHD/自閉友善「可移除倒數」開關**（Happy Kids Timer / Visual Timer for Kids 標配）：低成本、擴大可服務族群。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢 → 做出來能撐 Pro 價值感。
- 真機背景停鈴 / 貪睡尚未收尾 → 上架前務必驗（見 §2A）。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-06-27 刷新；本次以 Mac App Store / 視覺計時器類重新掃）

| App | 模式 | 可借鏡的點 |
|---|---|---|
| **Woohoo Toddler Clock** | 免費 5 條可編輯 program 起步、雲端備份要登入 | okay-to-wake 視覺燈號、routine cloning（睡前/午睡/旅行/quiet time 各一套）、可自訂顏色與圖片 |
| **Sun to Moon Sleep Clock** | iOS/Android，日/夜模式 | **stars 逐顆消失到天亮**的視覺倒數；獎勵兌換經濟（集獎勵→換 Sun/Moon 角色禮物）；夜間 sleep sounds + nap timer |
| **Time To Wake Night Light** | 免費 + IAP | **純視覺、無聲**（不吵醒同房手足）；綠燈 +「離上學/螢幕時間還有多久」**過渡倒數** |
| **Sleep Clock** | 免費 | 最精簡的色彩語意：藍燈=睡、黃燈=起 → 印證「一個顏色就懂」對學齡前最有效 |
| **Visual Timer Kids / Visual Timer for Kids / KidTimer / Kiddo** | 免費 + IAP | **picture-reveal 視覺倒數**（60+ 圖隨倒數逐漸顯現、25+ 背景、20 音樂主題、20 完成音效）；明打 ADHD/自閉友善；適用刷牙/穿衣/screen time/quiet play |
| **Time Timer App** | 付費品牌 | 30 年招牌「紅色圓盤隨時間縮小」——**一個招牌視覺隱喻**就建立信任。提醒：SunnyWalker 該擁有一個專屬招牌視覺（水彩日出 / 花瓣）|
| **Happy Kids Timer: Home Chores** | IAP 解鎖自訂 chores | ADHD/自閉友善「可移除倒數」開關、家長命名獎勵 + 集星印獎狀 |
| **Timer for Kids – Routines** | 無帳號無廣告 | 角色 + 視覺計時器、專注單步 |

**全 on-device、與離線定位相容、最划算的借鏡（依 ROI 排序）：**
1. **okay-to-wake 綠燈 + 過渡倒數**（近零成本、辨識度最高，幾乎所有競品標配）→ 下一個免費亮點首選。
2. **分步 routine + 視覺計時器**（升級現有待辦語音）→ 直接對打競品核心。
3. **picture-reveal 視覺倒數 + stars 逐顆消失**（水彩吉祥物揭圖 / 星星，素材現成）。
4. **集星 → 吉祥物換裝/換場景的獎勵經濟**（接現有 star burst，天然 Pro 觸發點）。
5. **完成音效 + 主題/背景包**（Visual Timer Kids 模式）→ 天然 Pro+ 一次性內容包素材。
6. ADHD 友善「可移除倒數」開關、家長命名獎勵 + 集星印獎狀、每日肯定語（皆離線可做）。
7. **擁有一個招牌視覺隱喻**（Time Timer 教訓）：水彩日出 / 花瓣綻放當 SunnyWalker 的識別資產。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差、退訂客訴多；家長偏好一次性購買）。在此前提下衝量：

1. **守住「免費功能一個都不鎖」**（Lode 教訓：鎖既有功能 = 1 星 + Apple 觀感差）。轉化靠新增高感知價值，不是設限。
2. **把 Pro 做成「會持續長大的買斷」**：用 §2C 加值逐步免費追加給 Pro 用戶 → 墊高 lifetime 感，不漲價也值得買。
3. **時空膠囊語音 = 招牌轉化點**：情感價值高、免後端，列為下一個主推 Pro 亮點。
4. **多孩子 profile = 最自然付費觸發**（groups 已做一半）：新增第 2 個孩子時提示升級。
5. **獎勵兌換經濟 = 留存 + 轉化雙引擎**：免費可集星，Pro 解鎖整套吉祥物換裝/場景包——比「鎖功能」溫和、家長觀感好、又給孩子持續回來的理由。
6. **價格**：US$1.99 終身先驗付費意願（市場參考帶 US$2.99–8.99）。轉化好 → 不漲 base、改做第二個一次性「Pro+ 內容包」（床邊故事庫 / 主題包 / 換裝包 / 完成音效包，仍買斷）。
7. **轉化時機**：在「達免費上限」「新增第 2 孩子」「想錄 >5s 完整叫醒」「打開時空信箱」「想換吉祥物造型」這些高情緒時刻彈升級頁。
8. **家長信任 = 留存引擎**：離線 / 隱私在 App Store 截圖與描述首屏明講，是兒童類最強轉化文案。

> 短期最高 ROI：(a) okay-to-wake 綠燈 + 過渡倒數（免費亮點、近零成本）、(b) 時空膠囊語音、(c) groups→多孩子 profile + 起床 streak/月曆、(d) 集星→吉祥物換裝獎勵經濟。

---

## 5. note 整理結果（週六，依規則執行）

今天是**週六**，依排程規則執行 weekly 彙整 + 舊 note 整理：

1. **產生 weekly**：已建立 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly）。內容＝把 06-23～06-27 五份 daily 的「未做完」項目去重彙整成單一 rolling backlog，並附「本週已完成」清單（勾除留底）。**此後請以 weekly 當唯一待辦清單。**
2. **做完的勾除**：本週已落地的（mic.badge 換、accessibilityLabel 包 Text、foregroundAlarmTick 2s、clock 分鐘翻面重繪、flowerImage 縮 512px、catalog en 補齊、emoji 清除）在 weekly 以 `[x]` 留底、不再列入 open backlog。
3. **舊 daily 整理（刪除）**：依排程文「做完的就刪除」+「整理」，已把 `SunnyWalker_2026-06-23.md` / `06-24.md` / `06-25.md` / `06-26.md` 四份「已被 weekly 完整彙整」的 daily **刪除**。四份皆在 git（commit `03c2fbe` / `2c76155` 已納版控）→ 若要復原：`git checkout 03c2fbe -- Ai_review/`。保留：本檔 `06-27.md`（今日 daily）+ `06-27-weekly.md`（rolling backlog）。
   - 若你比較想「保留每日 daily、只在 weekly 勾除」而不刪檔，跟我說，我下次改成不刪、只彙整。
4. **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫過 `/ai_review/`。本批寫入 `Ai_review/`。要統一成小寫跟我說，一次改名 + 更新排程路徑。

---

## 6. 本次進度（2026-06-27）

- [x] Review 專案結構 + 對帳 06-26 → 今天（git log：3 commit 皆純文件，未碰 open 項）
- [x] 逐條 file:line 對現行 code 複查：確認 5 項已修（mic.badge / foregroundAlarmTick 2s / clock 分鐘翻面重繪 / flowerImage 縮圖 / catalog 359 key 0 缺 en）
- [x] 確認仍 open：前景 handleAutoStop 缺 WakeRecord（一行）、StopAlarmIntent 6 處中文無 en、WakeHistory 匯出模板、orchestrator 4 項
- [x] 更正 06-26 一條：unlockTick 其實綁在 HomeView 主 body（非開著的 sheet），每秒常駐 → 改列 §1B 低度省電項
- [x] 競品掃描刷新（Mac App Store / 視覺計時器類；新增 Sleep Clock 色彩語意、Visual Timer Kids picture-reveal、Time Timer 招牌視覺教訓）
- [x] 兒童時間小幫手優缺點 + 商業/變現更新（§3 / §4）
- [x] note 整理：產生 `06-27-weekly.md`、勾除已完成、刪除 06-23～06-26 舊 daily（git 可復原）
- [ ] 等你勾選 §1/§2 要動手的項目 → 我再實作（本檔未改任何 app/orchestrator code）

**建議優先序**：
1. **前景 `handleAutoStop` 補 insert timeout WakeRecord**（§2A #2）— 一行，補齊統計缺口，工最小。
2. **真機背景停鈴整夜驗證**（§2A #1）— 上架品質最高風險，硬指標（需你在 Xcode/真機跑）。
3. **orchestrator robustness**（§1C）— `ring.py` flock + `consecutive_failures` 只算真失敗，避免半夜誤退場。
4. 商業：**okay-to-wake 綠燈（免費亮點）** + **時空膠囊語音** + **集星→吉祥物換裝獎勵經濟**（§4 最高 ROI）。
5. i18n 收尾（§1A，StopAlarmIntent + 匯出模板）+ §1B 兩個 1Hz timer 放寬（省電，工小）。
