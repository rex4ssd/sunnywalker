# SunnyWalker — AI Review 2026-06-26（Fri）

> 自動排程產生。延續 `SunnyWalker_2026-06-25.md` / `06-24.md` / `06-23.md`。
> App 定位：7 歲小孩用、**100% 離線**語音互動鬧鐘 / 兒童時間小幫手。iOS 26、SwiftUI、AlarmKit。Swift ≈ **12.75k LOC**。
> Repo 同時含 Python `claude_loop` 4-agent orchestrator。
>
> 🔎 **本檔一樣是「先寫下來給你看」——除了寫回本檔，沒有改任何 code。** 你勾選要做的，我再動手。
> 今天是**週五**，非週六 → 依排程規則**不刪除舊檔、不產生 weekly**。下一個週六（**2026-06-27，明天**）才把未做完項目存成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly）。

---

## 0. 自上次 review（06-25）以來的變化 — 先對帳

🎉 **好消息：你把 06-25 點名的快速可收項目都做掉了。** `git log` 顯示 06-25 有 3 個新 commit，且我已逐項對 code 複查確認落地：

| commit | 內容 | 複查結果 |
|---|---|---|
| `6c11c84` | perf/a11y follow-ups（symbol / VoiceOver / timers / flower 縮圖）| ✅ 全部到位，見下方逐條 |
| `ddc2fa0` | 強制 alarm-toggle VoiceOver label 走 `LocalizedStringKey` | ✅ `AlarmListView` 已包 `Text(...)` |
| `2c76155` | 把 06-24 / 06-25 review 報告納入版控 | ✅ 純文件 |

### ✅ 已修（06-25 → 今天已解，逐條 file:line 複查）

1. **`mic.badge.checkmark` 無效符號 → 已換。** 全專案 grep `mic.badge` 只剩 `RingtonePickerSheet.swift:201` 的 `mic.badge.plus`（合法符號）。原 `AlarmEditorView` 那處已改掉，不會再 log `No symbol named`。✅
2. **`accessibilityLabel` 走 verbatim String → 已改 `Text(LocalizedStringKey)`。** `AlarmListView.swift:165 / :172` 現在都是 `.accessibilityLabel(Text(...))`，並補了「開啟鬧鐘 / 關閉鬧鐘」的 en 值 → VoiceOver 英文模式不再唸中文。✅
3. **HomeView 1Hz Timer 常駐耗電 → 已大幅優化。** `foregroundAlarmTick` 1s→**2s**（:75）；`ClockHeaderView.tick` 雖仍 1Hz，但 `onReceive` 改成「只在**分鐘桶翻面**才更新 state」（:976 區），砍掉每秒 numericText 轉場重繪——床頭整夜亮屏的主要耗電來源已解。`unlockTick`（:1025）刻意保留 1s，但**被綁在開著的設定 sheet、驅動 mm:ss 倒數**，屬合理常駐，**不再視為缺陷**。✅
4. **花心照未縮圖、整張常駐記憶體 → 已修。** `AppSettings.saveFlowerImage`（:385 區）存檔前用新加的 `downscaled(_:maxDimension:)` 縮到 **≤512px**、`format.scale=1`（避免 @3x 把記憶體膨脹回去），記憶體與磁碟都不再扛數 MB 原圖。✅

> 結論：06-25「建議優先序」的前 3 項（symbol / VoiceOver / timer）+ 花心縮圖 **全做完**。剩下的是工較大或需真機的項，往下看。

---

## 1. 還沒做的優化（複查後仍 open）

### 1A. 🟡 i18n — 剩「不走 String Catalog」的三類（catalog 本身仍乾淨）

> catalog 路徑（`Text()`）06-24 起就乾淨；剩下全是不經 catalog 的：

| 嚴重度 | 位置 | 內容 | 修法 |
|---|---|---|---|
| 🟢（捷徑/系統 UI）| `Intents/StopAlarmIntent.swift:16,25,64,70` | `title="停止鬧鐘"/"關閉鬧鐘"`、`@Parameter(title:"鬧鐘識別碼")` 是 `LocalizedStringResource`，無 en 值 → 在「捷徑」App / 系統 intent UI 露中文 | 補 en 值（AlarmKit/Intents 先天 edge，優先序中低）|
| 🟢（家長匯出）| `Views/Settings/WakeHistoryView.swift:200-221` | 匯出 `.md` 全中文模板（`SunnyWalker_起床紀錄_…` 檔名 + `static methodLabel(_:)` 回 `"語音"/"按鈕"` 純 String）| 英文模式輸出英文模板；分享給英語家庭才乾淨。優先序低 |

> 註：列表顯示用的 `methodLabel`（:121, `LocalizedStringKey`）已乾淨，只有**匯出**那條 `static methodLabel`（:218）是純 String。家長頁畫面本身英文模式 OK。

### 1B. 🟡 CPU / RAM（剩 1 項待查）

- **HomeView 三大耗電源已收兩個**（foregroundAlarmTick 2s、clock 分鐘翻面才重繪），`unlockTick` 合理保留。✅ 這批基本收尾。
- **UserDefaults `didSet` 寫入抖動**（沿用 06-23/24 判斷，**尚未複查**）：陣列設定任一變更整包重寫，若綁 slider/drag → debounce。**仍掛 open，待下次抽查確認是否真的綁拖曳互動。**

### 1C. 🟡/🟢 Orchestrator（Python，仍 open，未動）

| 嚴重度 | 位置 | 問題 | 修法 |
|---|---|---|---|
| 🟡 | `orchestrator.py:52-55` `TOKEN_LIMIT_PATTERNS` | 仍含裸 `"429"`/`"credit"`/`"billing"`/`"quota"` 子字串；agent 讀到含這些字的原始碼 / 測試輸出（例如 HTTP 範例、帳務字眼）→ 誤觸 4h cooldown。註：偵測已是 tail `[-4000:]`（:61）✅，但**比對範圍是整段 log tail 不是只掃 orchestrator 自身 error 行** | 改成只掃 orchestrator 包裝的 error 行，或拿掉裸 `429`/`credit` |
| 🟡 | `lib/ring.py:124-141` `append_in_progress`/`append_failed` | `RING.open("a")` append **無鎖**；手動 `sw next` 與 supervisor 並跑 → baton 交錯損毀 | `fcntl.flock` 鎖 `ring.lock` |
| 🟡 | `supervise.py:174,238,300` `consecutive_failures` | 仍把（疑似）cooldown / approval gate / 非工作時段也累加成 failure；`max_failures` 易誤觸退場（:224）| 只算真正 FAILED/timeout/token-pause，cooldown/approval/off-hours 不計 |
| 🟢 | `orchestrator.py:71` `_live_status` | 每 3s `read_text().splitlines()` 讀**整個** log（會長到 MB；token 偵測那條 :61 已 tail，這條沒）| seek tail N KB |

> 註：`except Exception: pass` 這批本次 grep **已掃不到**（先前 06-24 點名的吞錯，看來已順手清掉或非如數量），暫從清單移除，下次若再發現再補。

---

## 2. 各項功能：缺陷 & 未完成（逐條更新狀態）

### 2A. 未解 bug / 待真機驗證

1. 🔴 **背景整夜自動停鈴** — 架構限縮為「keep-alive ≤10 分鐘」；**真機整夜 + 耗電驗證仍待做**。1 星負評最高風險點，上架前務必驗。**（仍 open，需 Xcode + 真機，排程環境做不了）**
2. 🟡 **前景 ringTimeout 不寫 WakeRecord — 確認仍 open（一行缺口）。** `AlarmRingView.handleAutoStop()`（:311-327）只 `playEffectOnce("timeout_sad.wav")` + `dismiss()`，**沒有** `modelContext.insert(WakeRecord(dismissMethod:"timeout"))`；對照同檔 `handleWakeUp()`（:362-370）成功路徑有 insert。背景路徑已由 `HomeView.drainTimeoutRecords()`（:471, `dismissMethod:"timeout"`）補上 → **只剩「App 開在前景、響到逾時自動關」這一筆漏記**，導致回應率/準時率分母低估。補一行 insert 即與背景一致。**工最小、建議順手收。**
3. 🟡 **溫和提醒長音截斷** — 已用短 CAF + 堆疊 burst 修好並真機驗證；仍 open：(a) cutoff-probe 找 iOS 真正截斷點、(b) ≥30s 錄音自動裁切 + UI 警告。
4. 🟡 **貪睡（snooze）完全未實作** — 原型已全 revert，`snooze/貪睡` 字串散在 7 個檔。卡在需 Xcode 驗證 iOS 26 `AlarmConfiguration` initializer。
5. 🟢 **strict mode 死碼殘留** — `requireAppToStop`、`scheduleNagsIfNeeded`、AudioRecorder strict gate、孤兒「貪睡模式」字串 → 清理待辦。

### 2B. 未做的功能 TODO

- **時空膠囊語音（Voice Time Capsule）** — UNUserNotificationCenter 本地排程 + 「時空信箱」UI。**被點名為 Pro 招牌、免後端、優先做。**
- 小孩錄音 + CloudKit 家庭同步（Pro v2，需重過 Kids 隱私審）。
- 成長聲音自動剪輯（on-device 可行）、睡前床邊故事（搭 BedSideManager）。
- 視覺二/三波（A5 視差、A8 字型、B4 彩蛋、B5 動態鬧鐘卡、C 瞳孔細節）。
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
- 報時 + 待辦語音 + 多人群組 + Dynamic Type + VoiceOver（新近補強）→ 縱深 & 無障礙到位。

### 缺點 / 可補強（對齊 §4 競品掃描）
- **缺「可視化分步 routine + 視覺計時器」**：競品核心都是「一步步走完早晨/睡前流程 + 倒數」。SunnyWalker 的「待辦語音提醒」是雛形 → **升級成分步 routine + 倒數計時器**就直接對打。
- **缺 okay-to-wake 顏色燈號**：競品標配「紅燈睡 / 綠燈可起床」。加日夜情境的綠色「可以起床了」信號，近零成本高辨識，對學齡前特別有效。**仍是近零成本最高 ROI 的免費亮點。**
- **缺「picture-reveal 視覺倒數」**（本次新觀察，見 §4）：競品（Visual Timer for Kids 系列）主打「圖片隨倒數逐漸顯現」。SunnyWalker 的水彩吉祥物天生適合做這種揭圖動畫，幾乎是現成素材的再利用。
- **缺獎勵兌換經濟**（本次新觀察）：Sun to Moon 用「集 snooze 獎勵→換吉祥物禮物」做長期動機。SunnyWalker 已有 star burst，可把「集星」接到吉祥物換裝/換場景，**天然 Pro 觸發點**。
- **起床數據太淺**：只記單筆，缺 streak / 月曆 / 趨勢 → 做出來能撐 Pro 價值感。
- 真機背景停鈴 / 貪睡尚未收尾 → 上架前務必驗（見 §2A）。

---

## 4. 商業 / 變現：試用轉收費、獲利長紅

### 4A. 競品掃描（2026-06-26 刷新；★ 為本次新增）

| App | 模式 | 可借鏡的點 |
|---|---|---|
| **Woohoo Toddler Clock** | 免費 5 條可編輯 routine 起步、雲端備份要登入 | okay-to-wake 視覺燈號、routine cloning（睡前/午睡/旅行/quiet time 各一套）|
| ★ **Sun to Moon Sleep Clock** | iOS/Android，日/夜模式 | **獎勵兌換經濟**：集 snooze 獎勵→換 Sun/Moon 角色禮物（換裝/收集）做長期動機 + 夜間 sleep sounds |
| ★ **Visual Timer for Kids / Visual Timer Kids** | 免費 + IAP | **picture-reveal 視覺倒數**：圖片隨時間逐漸顯現（200+ 圖、主題、完成音效）；明打 ADHD/自閉友善、適用刷牙/穿衣/screen time |
| ★ **Lil Planner / Visual Schedule Daily Routine** | 圖卡排程 | 大圖大字、圖卡式「一天流程」規劃，家長與孩子共用 |
| **Kids AlarmClock** | 卡通英雄叫醒 | **每日正向肯定語**（離線、與定位相容）|
| **Happy Kids Timer: Home Chores** | IAP 解鎖自訂 chores | ADHD/自閉友善「可移除倒數」開關、家長命名獎勵 + 集星印獎狀 |
| **REMI / Time To Wake Night Light** | 硬體+app / 免費+IAP | 多合一情境：okay-to-wake 燈 + 夜燈 + 故事播放器 + **綠燈 + 過渡倒數** |
| **Alarmy** | 免費 + IAP US$4.99 起 | 「mission 才能關鈴」強互動——「我起床了」可往趣味關卡加 |

**全 on-device、與離線定位相容、最划算的借鏡**：
1. **okay-to-wake 綠燈 + 過渡倒數**（近零成本、辨識度最高）→ 下一個免費亮點首選。
2. **分步 routine + 視覺計時器**（升級現有待辦語音）→ 直接對打競品核心。
3. ★ **picture-reveal 視覺倒數**（水彩吉祥物揭圖，素材現成）。
4. ★ **集星→吉祥物換裝/換場景的獎勵經濟**（接現有 star burst，天然 Pro 觸發點）。
5. 家長命名獎勵 + 集星印獎狀、每日肯定語（皆離線可做）。

### 4B. 試用 → 收費（現價 US$1.99 終身，已鎖）

維持買斷、不轉訂閱（兒童 app 訂閱觀感差、退訂客訴多；家長偏好一次性購買）。在此前提下衝量：

1. **守住「免費功能一個都不鎖」**（Lode 教訓：鎖既有功能 = 1 星 + Apple 觀感差）。轉化靠**新增高感知價值**，不是設限。
2. **把 Pro 做成「會持續長大的買斷」**：用 §2C 加值逐步免費追加給 Pro 用戶 → 墊高 lifetime 感，不漲價也值得買。
3. **時空膠囊語音 = 招牌轉化點**：情感價值高、免後端，列為下一個主推 Pro 亮點。
4. **多孩子 profile = 最自然付費觸發**（groups 已做一半）：新增第 2 個孩子時提示升級。
5. ★ **獎勵兌換經濟 = 留存 + 轉化雙引擎**：免費可集星，Pro 解鎖整套吉祥物換裝/場景包——比「鎖功能」溫和、家長觀感好、又給孩子持續回來的理由。
6. **價格**：US$1.99 終身先驗付費意願（市場參考帶 US$2.99–8.99）。轉化好 → **不漲 base、改做第二個一次性「Pro+ 內容包」**（床邊故事庫 / 主題包 / 換裝包，仍買斷）。
7. **轉化時機**：在「達免費上限」「新增第 2 孩子」「想錄 >5s 完整叫醒」「打開時空信箱」「想換吉祥物造型」這些**高情緒時刻**彈升級頁。
8. **家長信任 = 留存引擎**：離線 / 隱私在 App Store 截圖與描述**首屏**明講，是兒童類最強轉化文案。

> 短期最高 ROI：**(a) okay-to-wake 綠燈 + 過渡倒數（免費亮點、近零成本）、(b) 時空膠囊語音、(c) groups→多孩子 profile + 起床 streak/月曆、(d) 集星→吉祥物換裝獎勵經濟。**

---

## 5. note 整理結果

- 現存 `Ai_review/`：`SunnyWalker_2026-06-23.md`、`06-24.md`、`06-25.md`，加本檔 `06-26.md`。
- 今天**週五，非週六** → 依排程規則**不刪除舊檔、不產生 weekly**。**明天週六（2026-06-27）**才把「未做完」彙整成 `Ai_review/SunnyWalker_2026-06-27-weekly.md`（原格式 + weekly），屆時把已做掉的（06-25 §0 那 4 條 ✅ + 06-24/06-23 早收的）勾除、只留 open。
- 本檔 §1/§2 即「未做完」彙整，可直接當明天 weekly 的素材。
- ⚠️ **資料夾大小寫**：實際是 `Ai_review/`（大寫 A），排程文寫過 `/ai_review/`。本檔寫入 `Ai_review/`。要統一成小寫跟我說，一次改名 + 更新排程路徑。

---

## 6. 本次進度（2026-06-26）

- [x] Review 專案結構 + 對帳 06-25 → 今天（git log：3 commit，皆 AI-review follow-up）
- [x] 逐條 file:line 複查 06-25 open 項 → **4 項已修**：`mic.badge`✓換、accessibilityLabel✓包 Text、HomeView timer✓（2s + 分鐘翻面重繪）、flowerImage✓縮 512px
- [x] 確認仍 open：前景 `handleAutoStop` 仍缺 timeout WakeRecord insert（一行）、export 模板 i18n、StopAlarmIntent i18n、orchestrator 4 項（token pattern / ring flock / consecutive_failures / live_status 全讀）
- [x] 競品掃描刷新（新增 Sun to Moon 獎勵經濟、Visual Timer picture-reveal、Lil Planner 圖卡排程）+ 商業/變現更新
- [x] note 整理（週五，不刪除/不 weekly；明天週六才出 weekly）+ 建立今日報告（本檔）
- [ ] 等你勾選 §1/§2 要動手的項目 → 我再實作（**本檔未改任何 code**）

**建議優先序**：
1. **前景 `handleAutoStop` 補 insert timeout WakeRecord**（§2A #2）— 一行，補齊統計缺口，工最小。
2. **真機背景停鈴整夜驗證**（§2A #1）— 上架品質最高風險，硬指標（需你在 Xcode/真機跑）。
3. **orchestrator robustness**（§1C）— `ring.py` flock + `consecutive_failures` 只算真失敗，避免半夜誤退場。
4. 商業：**okay-to-wake 綠燈（免費亮點）** + **時空膠囊語音** + **集星→吉祥物換裝獎勵經濟**（§4 最高 ROI）。
5. i18n 收尾（§1A，StopAlarmIntent + 匯出模板，優先序低）。
