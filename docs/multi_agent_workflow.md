# SunnyWalker 4-Agent 自動化開發流程（Ring 模式）

> 目標：1 週內由 4 個 AI 角色協作完成 iOS App，使用者只需執行 `./run.sh next`，
> 所有狀態與交棒透過**單一 ring 檔**（`orchestrator/ring_process.md`）。

## 0. 為什麼用 ring 檔（append-only baton）

- **單一真相**：人類 5 秒掃完知道現在到哪了，不用 grep 12 個檔
- **斷電可續**：orchestrator crash 也沒關係，狀態在檔裡，下次 `./run.sh next` 接著跑
- **AI 友善**：每個 agent 只讀一個 markdown 檔，不用解析多個 JSON
- **語意對**：A→B→C→D→A→B→...→ 真的是一個環

## 流程示意

```
ring_process.md (append-only)
       │
       │  D 寫完 Day N: "→ End of Day N"，並寫明日 A 的 brief
       │
       ▼
┌──────────────────────────────────────────────┐
│ AI A reads ring, sees last = "End of Day N"  │
│ → my turn (Day N+1), reads D's brief         │
│ → coding → appends entry → "→ Hand off to B" │
└────────────────┬─────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────┐
│ AI B reads ring, sees last = "Hand off to B" │
│ → validates → appends entry → "→ to C"       │
└────────────────┬─────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────┐
│ AI C reads ring, sees "Hand off to C"        │
│ → reports + git push → appends → "→ to D"    │
└────────────────┬─────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────┐
│ AI D reads ring, sees "Hand off to D"        │
│ → reviews + writes Day N+1 brief             │
│ → appends → "→ End of Day N"                 │
└──────────────────────────────────────────────┘
```

## Orchestrator 的角色（不是調度，是安全網）

`orchestrator.py` **不再做業務調度**，那個是 ring 檔自己做的。它只負責：

1. **找下個 agent**：parse ring 最後一筆，看 `→ Hand off to X`
2. **spawn `claude -p`**：用對應角色的 prompt
3. **enforce 安全**：timeout、tool 白名單、不准 push main
4. **記 verbose log**：把 stdout 存到 `logs/<date>/<x>_<role>.log`（debug 用）
5. **異常時**：在 ring 上蓋 `Status: FAILED`，下次跑人類要先處理

---

## 1. 角色分工

```
┌─────────────────────────────────────────────────────────┐
│  使用者：./run.sh today                                  │
└──────────────────┬──────────────────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  AI A: Coder        │  輸入：spec.md + 昨日 review
        │  寫 Swift 程式碼     │  輸出：code change + a_code.log
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │  AI B: Validator    │  輸入：A 寫的程式碼
        │  跑 xcodebuild      │  輸出：b_validate.log
        │  跑 swiftlint       │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │  AI C: Reporter+CI  │  輸入：A、B 的 log
        │  寫日報、git commit │  輸出：c_report.md + git push
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────┐
        │  AI D: Reviewer     │  輸入：A、B、C 全部產出
        │  評審今日成果        │  輸出：d_review.md + 明日 brief
        │  寫明日待辦          │
        └─────────────────────┘
```

### 1.1 AI A — Coder
- **模型**：`claude-sonnet-4-6`（寫程式夠用、便宜）
- **權限**：可讀寫 `SunnyWalker/` 下所有 Swift 檔
- **不可做**：git commit、執行 build、修改 orchestrator 自己
- **輸入**：
  - `docs/swift_native_spec.md`（規格書）
  - `orchestrator/logs/YYYY-MM-DD-1/d_review.md`（昨日 reviewer 寫的明日 brief）
  - 當前 Xcode 專案狀態
- **輸出**：
  - 新增/修改的 `.swift` 檔
  - `orchestrator/logs/YYYY-MM-DD/a_code.log`（純文字，記錄改了什麼、為什麼）
  - `orchestrator/logs/YYYY-MM-DD/a_status.json`（結構化：今日完成 task ID、剩餘 task）

### 1.2 AI B — Validator
- **模型**：`claude-haiku-4-5`（只跑指令、判斷成敗，便宜）
- **權限**：可執行 shell（xcodebuild、swiftlint），可寫 log
- **不可做**：改 Swift 程式、git commit
- **輸入**：
  - `scripts/validate.sh`
  - `a_code.log`（看 A 改了什麼，決定要跑哪些測試）
- **輸出**：
  - `b_validate.log`（原始 stdout）
  - `b_summary.md`（人類/AI 可讀的摘要：編譯通過 / 3 個 warning / 5 個 error）
  - `b_status.json`（`{"build": "pass", "tests": "fail", "errors": [...]}` ）

### 1.3 AI C — Reporter + CI
- **模型**：`claude-haiku-4-5`（寫摘要、跑 git）
- **權限**：可執行 `git add/commit/push`，可寫 markdown
- **不可做**：改 Swift 程式、改測試
- **輸入**：`a_code.log` + `b_summary.md`
- **輸出**：
  - `c_report.md`（日報：今日完成項、build 狀態、明日預告）
  - `git commit -m "Day N: <主題> [A:B:]"`（標準化 commit message）
  - `c_status.json`

### 1.4 AI D — Reviewer
- **模型**：`claude-opus-4-6`（最強模型，evaluator 角色）
- **權限**：唯讀所有檔案，可寫 review 與明日 brief
- **不可做**：改任何程式碼、git commit
- **輸入**：A、B、C 全部今日 log + spec.md
- **輸出**：
  - `d_review.md`（評估今日進度：對得起 spec 嗎？品質如何？）
  - `d_next_brief.md`（明日 AI A 要做什麼，具體到檔案與 function）
  - `d_status.json`（`{"day": 3, "completion_pct": 42, "blockers": [...], "verdict": "on_track"}`）

---

## 2. 檔案結構

```
SunnyWalker/                       # 你的 git repo 根目錄
├── SunnyWalker.xcodeproj           # iOS 專案（AI A 改這裡）
├── SunnyWalker/                    # Swift 源碼
│   └── ...（依 swift_native_spec.md）
│
├── docs/
│   ├── first_idea.md
│   ├── swift_native_spec.md       # 規格書（不要動）
│   └── multi_agent_workflow.md    # 本文件
│
├── orchestrator/                   # 自動化系統
│   ├── orchestrator.py            # 主程式
│   ├── config.yaml                # 模型、路徑、API key
│   ├── prompts/
│   │   ├── 01_coder.md
│   │   ├── 02_validator.md
│   │   ├── 03_reporter.md
│   │   └── 04_reviewer.md
│   ├── logs/
│   │   ├── 2026-05-29/
│   │   │   ├── a_code.log
│   │   │   ├── a_status.json
│   │   │   ├── b_validate.log
│   │   │   ├── b_summary.md
│   │   │   ├── b_status.json
│   │   │   ├── c_report.md
│   │   │   ├── c_status.json
│   │   │   ├── d_review.md
│   │   │   ├── d_next_brief.md
│   │   │   └── d_status.json
│   │   └── 2026-05-30/
│   │       └── ...
│   └── requirements.txt
│
├── scripts/
│   ├── dev.sh                     # 多功能：git ca / validate / debug
│   ├── validate.sh                # xcodebuild test + swiftlint
│   └── git_ca.sh                  # 標準化 commit
│
├── run.sh                         # 唯一進入點
└── README.md
```

---

## 3. 一週開發節奏

| Day | AI A 主題 | 預期產出 |
|---|---|---|
| 1 | 專案骨架 + Models + Theme | `SunnyWalkerApp.swift`, `Alarm.swift`, `GhibliColors.swift`, build pass |
| 2 | HomeView + AlarmListView | 主畫面雲朵動畫、鬧鐘卡片列表（假資料） |
| 3 | AlarmScheduler + 通知權限 | 能成功收到 local notification |
| 4 | AudioRecorder + RecordingView | 能錄音、能播放 |
| 5 | SpeechRecognizer + AlarmRingView | 離線辨識「我起床了」、停止播放 |
| 6 | ParentalGate + Settings | 家長閘門、整合 SwiftData CRUD |
| 7 | Polish + 上架素材 + Archive | App icon、screenshot、TestFlight build |

**每天執行**：
```bash
cd /Users/lion/Documents/SunnyWalker
./run.sh today
# 約 30–60 分鐘跑完，產出今日 log 與 commit
```

**只跑單一 agent**（debug 用）：
```bash
./run.sh coder         # 只跑 A
./run.sh validator     # 只跑 B
./run.sh review        # 只跑 D（重評估）
```

---

## 4. Ring 檔格式

### 4.1 一筆完整 entry 長這樣

```markdown

## [A] Day 3 — 2026-05-31 09:42:13+08:00
Status: DONE
Model:  claude-sonnet-4-6

### What I did
- Created Services/AlarmScheduler.swift (async wrapper around UNUserNotificationCenter)
- Modified Models/Alarm.swift (added weekday repeat)

### Files
+ SunnyWalker/Services/AlarmScheduler.swift
~ SunnyWalker/Models/Alarm.swift

### Stamps
Spec section 7 Day 3 satisfied
No third-party SDK added
Weekday repeat not yet wired in UI

### For next (B — Validator)
Please run `scripts/validate.sh`. Expect build pass, no tests yet, 1 lint warning
about TODO in AlarmScheduler.

→ Hand off to B
```

### 4.2 狀態判讀規則

| Last entry pattern | 意義 | 下個 agent |
|---|---|---|
| `Status: DONE` + `→ Hand off to X` | X 該上場 | X |
| `Status: DONE` + `→ End of Day N` | 一天結束 | A (Day N+1) |
| `Status: IN_PROGRESS` | 還在跑 / crash 了 | 同一個 agent retry |
| `Status: FAILED` | 出事，停 | **人類** 處理後手動 force-run |

### 4.3 Verbose log（debug 用）

ring 是給 AI/人類看大局的；想看細節時去 `orchestrator/logs/<DATE>/<x>_<role>.log`，
裡面是 `claude -p` 的完整 stream-json 對話。出事時看這個。

---

## 5. 失敗處理

| 情境 | 處理 |
|---|---|
| AI A 寫的程式 build fail | B 標記 `status:fail` → D 看到後在 next_brief 加「先修 build」 |
| AI A 卡住 30 分鐘沒進度 | orchestrator timeout，記 `status:timeout`，D 評估是否需要拆 task |
| `claude` CLI 報錯 (API 額度) | orchestrator 重試 3 次，仍失敗則寫 `_error.log` 停止 |
| 連續 2 天 D 評 `verdict:off_track` | run.sh 不再自動跑，提示使用者手動介入 |

---

## 6. 安全與成本

### 6.1 模型成本估算（USD/天）
| Agent | 模型 | tokens/run | 估價 |
|---|---|---|---|
| A Coder | Sonnet 4.6 | 30k in + 15k out | ~$0.32 |
| B Validator | Haiku 4.5 | 8k in + 2k out | ~$0.02 |
| C Reporter | Haiku 4.5 | 10k in + 3k out | ~$0.03 |
| D Reviewer | Opus 4.6 | 40k in + 10k out | ~$1.20 |
| **每日合計** | | | **~$1.60** |
| **7 天合計** | | | **~$11.20** |

實測會有出入，config.yaml 可以全部降到 Sonnet 4.6 省成本。

### 6.2 git 安全
- AI C 只能 `commit` + `push` 到 `dev/auto` 分支，不能 push 到 `main`
- 每晚最後人類手動 `git merge dev/auto → main`，這是 human gate

### 6.3 不寫進 log 的東西
- API Key（用環境變數 `ANTHROPIC_API_KEY`）
- 你的 Apple Developer 帳密
- 任何個人錄音檔內容

---

## 7. 1 週後驗收 checklist

- [ ] Xcode build pass，可在模擬器跑
- [ ] 真機收到 local notification
- [ ] 離線辨識「我起床了」可以關掉鬧鐘
- [ ] Parental Gate 題目大人能解、小孩不會
- [ ] 視覺套上 Ghibli 風（背景、字型、按鈕、龍貓）
- [ ] App Icon、3 張 screenshot、Privacy Policy URL 備齊
- [ ] TestFlight build 上傳成功
- [ ] 7 份 d_review.md 都是 `verdict:on_track`

達到 ≥6 項視為成功，可送 App Store 審查。
