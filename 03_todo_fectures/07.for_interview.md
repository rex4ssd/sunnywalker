# SunnyWalker — 面試技術摘要

> 一句話：**我用 4 個 AI agent 自動接力的開發流程，每天自動產出一段進度，造了一個給 7 歲小孩用的「語音互動鬧鐘」iOS app。**
> 所以這專案有兩個可以聊的層面：一個是 **app 本身的 iOS 技術**，一個是 **「怎麼蓋這個 app」的自動化開發框架**。

---

## 1. 專案是什麼

兩個主體：

1. **SunnyWalker（iOS app）** — 給 7 歲小孩的語音鬧鐘。iOS、Swift + SwiftUI、吉卜力水彩風、100% 離線、無廣告、無追蹤。小孩要「說出指定句子」才能關鬧鐘（也可選單純按鈕）。
2. **claude_loop（meta 框架）** — 一套可重用的「4-agent ring」自動開發框架，每天自動把 app 往前推一天。app 是它蓋出來的第一個產品。

面試時這兩塊都能講；下面分開整理。

---

## 2. Part A — AI 多代理開發框架（最特別的工程亮點）

### 2.1 核心概念：一個 append-only 的「接力棒」檔案

四個 AI 角色排成一個環，依序交棒：

```
A Coder ─→ B Validator ─→ C Reporter+CI ─→ D Reviewer ─┐
↑                                                       │
└────────────────── 換日 ←───────────────────────────────┘
```

| 角色 | 工作 | 用的模型 | 每日成本估 |
|---|---|---|---|
| A Coder | 寫 Swift 程式 | Sonnet | ~$0.32 |
| B Validator | build + test + lint | Haiku | ~$0.02 |
| C Reporter+CI | 寫日報 + git commit/push | Haiku | ~$0.03 |
| D Reviewer | 誠實審查 + 寫明日待辦 | Opus | ~$1.20 |

所有狀態都寫在**單一一個 markdown 檔（ring 檔）**，每個 agent 只做一件事：讀最後一筆 → 看到 `→ Hand off to X` 就知道輪到誰 → 做完 append 自己的紀錄 + 蓋下一棒。D 收尾時寫 `→ End of Day N` 並留明天給 A 的 brief。

### 2.2 為什麼這樣設計（面試可以講的「決策理由」）

- **單一真相**：人類 5 秒掃完就知道進度到哪，不用 grep 十幾個檔。
- **斷電可續**：orchestrator 程式 crash / 關機都沒差，狀態在檔裡，下次 `sw next` 接著跑。
- **AI 友善**：每個 agent 只讀一個 markdown，不用解析多份 JSON。
- **語意正確**：A→B→C→D→A 本來就是一個環。

### 2.3 關鍵設計：orchestrator 不做調度，只做安全網

調度邏輯交給 ring 檔自己，`orchestrator.py` 只負責四件事：

1. 解析 ring 最後一筆，找下一個 agent。
2. 用對應角色 prompt spawn `claude -p`。
3. **強制權限分離**（最重要）：timeout、工具白名單。
4. 異常時在 ring 蓋 `FAILED`，下次要人類先處理。

**權限護欄（職責分離，像真實團隊）：**

- A 不能跑 `git`、不能跑 `xcodebuild`（只寫 code）。
- B 不能改 code（只驗證）。
- C 只能 push 到 `dev/auto`，**永遠碰不到 `main`**。
- D 唯讀（只審查）。

### 2.4 把「會壞掉」這件事當第一公民（reliability）

這是無人值守跑的系統，所以失敗處理是設計核心，不是補丁：

| 狀況 | 偵測方式 | 自動動作 |
|---|---|---|
| Token / rate limit | log 出現 "rate limit" / "429" / "quota" | 自動冷卻 4h + macOS 通知 |
| Build 壞了 | B 判定 red | C 照樣 commit 但加 `[BROKEN]` 前綴，交給 D 評估 |
| Crash / 斷電 | heartbeat 過期 + PID 已死 | `sw resume` 標 FAILED + 通知 |
| 需要人類介入 | D 標 `🚨 HUMAN ATTENTION` | 浮到 MAIN_ENTRY + 通知 |

額外特性：`sw next` 在「冷卻中 / 等審核 / 非工作時間」時 **exit 0**，所以可以直接丟進 cron（`*/30 * * * *`）無人值守跑；還能用 `schedule.csv` 設定每天的工作時段與「跑到第幾棒就停下來等我看」。

### 2.5 工程素養訊號

- 框架本身有 **pytest 39 個測試**（ring 解析、排程/冷卻/審核閘、報表產生、token limit 偵測）。
- 設計成**可重用**：`cp -r orchestrator` 到新專案、改一個 `config.yaml` 就能套到別的 app。
- 三種等價進入點（`sw` / `python sw.py` / `python -m orchestrator`），照顧不同使用習慣。

---

## 3. Part B — SunnyWalker iOS app 技術難點

### 3.1 技術棧

Swift + SwiftUI、**SwiftData**（持久化）、**AlarmKit**（鎖屏鬧鈴）、**AppIntents**（鎖屏停鬧鐘）、**AVFoundation**（錄音/播放）、**Speech / SFSpeechRecognizer**（on-device 語音辨識）。

### 3.2 最硬的問題：「睡著之後，怎麼用語音關鬧鐘？」

這題的難點不是寫 code，是 **Apple 平台限制**：

> 背景錄音只能「**延續**」一個在前景啟動的 audio session，**不能從背景重新啟動麥克風**。被 suspend 的 app 收到通知響鈴，也叫不起麥克風。

我評估了三條路並做了取捨（面試很好的「trade-off」題材）：

1. **Tier 1 — 床邊模式（前景常駐）**：螢幕壓到最暗但不進背景（`isIdleTimerDisabled = true`），前景下麥克風本來就能用，**零 App Review 風險**。
2. **Tier 2 — 整夜背景保活錄音**：技術上可行（睡前前景開 `.playAndRecord`、buffer 丟棄、帶 `UIBackgroundModes: audio` 進背景保活）。但對**兒童 app** 來說「橘色麥克風指示燈整夜長亮」幾乎一定被 App Review 打回，加上耗電 → 只當實驗功能、預設關。
3. **Shipping 採用 AlarmKit**：拿到 entitlement 後用系統級鬧鈴，鎖屏可靠響鈴；停鬧鐘走 `StopAlarmIntent` 再把 app 帶到前景做語音確認。

**結論**：最大阻礙是平台政策不是技術。最後選 AlarmKit + 前景語音，並把背景聆聽降為預設關閉的實驗選項。

### 3.3 其他值得聊的細節

- **SwiftData 安全遷移**：`Alarm` model 後加的欄位（`taskType`、`requireAppToStop`、`customDismissPhrase`）都設成 optional，搭配 lightweight migration，舊資料不會炸。一律透過 `effectiveXxx` computed property 讀取、不直接碰 optional —— 這是踩過雷後定的規矩。
- **語音辨識的現實限制**：`SFSpeechRecognizer` 大約 1 分鐘上限、且為短語設計，所以響鈴期間要自動 restart 辨識；支援自定關鬧鐘口令（除了預設「我起床了」之外）。
- **付費邊界收斂到單一來源**：所有免費版上限（鬧鐘 6 個、錄音 5 段…）集中在 `FeatureLimits` 一個 enum，未來接 StoreKit 只要把 `isPro` 翻成 `true`，全部頁面自動解鎖——不用改各頁。Code review 看一個檔就掌握全部 free/paid 邊界。
- **隱私 & 兒童合規**：`PrivacyInfo.xcprivacy` 標 `NSPrivacyTracking=false`；付費入口放在 `ParentalGateView`（家長閘門）後面，符合 Kids 類別規範。
- **無障礙**：`accessibilityReduceMotion`、VoiceOver labels。
- **測試**：app 端 60 pass + 1 skip。

---

## 4. 一分鐘電梯版（口說稿）

> 「我做了一個給小孩的語音鬧鐘 app，但更有意思的是我蓋它的方式：我設計了一套四個 AI agent 接力的自動開發流程——一個寫 code、一個編譯測試、一個寫日報跟 commit、一個做 code review 跟排明天的工作，每天自動把專案往前推。整個流程的狀態就靠一個 append-only 的 markdown 接力棒檔，所以斷電也能續跑，而且四個角色有嚴格的權限分離，像真實團隊一樣——寫 code 的不能 push、push 的碰不到 main。app 本身最難的部分是 iOS 不准你睡著後從背景啟動麥克風，所以我評估了前景常駐、整夜背景錄音、跟 AlarmKit 三種方案，最後因為兒童 app 的 App Review 風險選了 AlarmKit。」

---

## 5. 面試官可能追問 & 準備方向

- **「為什麼不用現成的 CI / LangGraph / CrewAI？」** → 我要的是極簡、可被人類 5 秒讀懂、斷電可續、且每個 agent 只讀一個檔的流程；單一 markdown ring 比框架更透明、好 debug。
- **「成本怎麼控？」** → 依任務難度分配模型：寫 code 用 Sonnet、跑指令用 Haiku、只有審查用貴的 Opus，一天約 US$1.5。
- **「怎麼確保 AI 不亂改？」** → 工具白名單 + 權限分離 + D 的誠實審查 + 框架自己有 39 個測試。
- **「最大的技術取捨是什麼？」** → 背景語音關鬧鐘：技術可行但兒童 app 合規不可行，所以改 AlarmKit。
- **「SwiftData 遇過什麼坑？」** → schema 演進：新欄位一律 optional + `effective` 存取器，避免遷移炸掉舊資料。
