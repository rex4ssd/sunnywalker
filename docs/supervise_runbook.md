# supervise.py — 長駐 supervisor runbook

> 不在電腦前的時段自動跑 `python sw.py today`，到設定時間或天數就乾淨退場。

## TL;DR — 出門前複製貼上

```bash
cd /Users/lion/Documents/SunnyWalker

nohup python supervise.py \
    --max-days 5 \
    --idle-min 30 \
    --stop-after 23:00 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

> **防呆**：重複執行會自動擋（lock file at `orchestrator/supervise.lock`）。
> 若舊 process crash 殘留 lock，重啟時自動清除。
> 錯誤訊息沉在 log 裡：`grep "已在執行" /tmp/sw_supervise.log`

回家後：

```bash
tail -50 /tmp/sw_supervise.log     # 看大致狀況
python sw.py status                 # MAIN_ENTRY
git log --oneline -20               # 看跑了哪幾個 day
```

---

## 1. 啟動方式

### A. 推薦（背景跑 + 時間到自動退）

```bash
nohup python supervise.py \
    --max-days 7 \
    --idle-min 30 \
    --poll-min 5 \
    --stop-after 23:00 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

- `nohup` + `disown` 關 terminal 也繼續跑
- `--stop-after 23:00` 到 23 點自動退（避免半夜還在跑你已經回家睡覺）
- `>>` append 模式，log 不會被重複執行蓋掉

### B. 前景跑（debug 用）

```bash
python supervise.py --max-days 1
```

直接看 stdout，按 Ctrl+C 乾淨退。

### C. 跑特定情境

| 情境 | 指令 |
|---|---|
| 出門 8 小時，最多跑 5 天 | `--max-days 5 --stop-after 18:00` |
| 整夜跑到天亮，最多 3 天 | `--max-days 3 --stop-after 06:00` |
| 只想跑完 Day 2 | `--max-days 1`（從現在算起 1 天） |
| 怕失敗燒 token，1 次失敗就停 | `--max-failures 1` |

---

## 2. 參數說明

| 參數 | 預設 | 意義 |
|---|---|---|
| `--max-days` | 7 | 完成 N 個 Day 就退場 |
| `--idle-min` | 30 | 跑完一天後 sleep 幾分鐘再開下一天 |
| `--poll-min` | 5 | cooldown/approval/window 擋住時 sleep 幾分鐘再試 |
| `--stop-after` | none | `HH:MM` 時間到就退場 |
| `--max-failures` | 3 | 連續 N 次 cycle 失敗就停 |
| `--model` | none | 統一覆蓋所有 agent 模型；不指定就吃 `config.yaml` |

---

## 2.5 模型選擇與成本

### config.yaml 預設（per-agent）

```yaml
agents:
  coder:     claude-sonnet-4-6           # A 寫 Swift
  validator: claude-haiku-4-5-20251001   # B 跑 build/test
  reporter:  claude-haiku-4-5-20251001   # C 寫日報 + git
  reviewer:  claude-opus-4-6             # D 評審 + 寫明日 brief
```

### 跑滿一天的成本估算

| 模式 | A | B | C | D | 約 USD/天 | 適用情境 |
|---|---|---|---|---|---|---|
| 預設（混合） | Sonnet | Haiku | Haiku | **Opus** | $1.50 | 真的要產 Day 1-7 完整 App |
| 全 Sonnet | Sonnet | Sonnet | Sonnet | Sonnet | $0.40 | 驗證框架 / 不在乎評審深度 |
| 全 Haiku | Haiku | Haiku | Haiku | Haiku | $0.10 | 純煙霧測試（D 評審會粗） |

### 一次性覆蓋全部 agent

```bash
# 全 Sonnet（省錢但 D 評審較淺）
nohup python supervise.py --max-days 5 --stop-after 23:00 \
    --model claude-sonnet-4-6 \
    >> /tmp/sw_supervise.log 2>&1 &
disown

# 全 Haiku（最便宜）
nohup python supervise.py --max-days 5 \
    --model claude-haiku-4-5-20251001 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

### 永久改某個 agent 的模型

編 `orchestrator/config.yaml`：
```yaml
agents:
  validator:
    model: claude-sonnet-4-6      # B 改 Sonnet（Haiku 在 B 偶爾沒寫 DONE entry）
    timeout_s: 1800
```

### 實戰建議

- **預算夠 + 認真做 SunnyWalker** → 預設（D Opus 最關鍵，影響明天 A 走對方向）
- **預算緊 / 想多跑幾天試流程** → 全 Sonnet（差距明顯但能用）
- **B 不穩** → 永久把 B 從 Haiku 改 Sonnet（其他保持），日成本 +$0.05
- **debug / 看流程** → 不用 supervisor，直接 `python sw.py --dry-run today` 只印 prompt 不燒 token

---

## 3. 退場條件（任一達到就乾淨結束）

| 條件 | 觸發 |
|---|---|
| `max_days` 達成 | 正常完成預期天數 |
| `stop_after` 時間到 | 你回來要用電腦 |
| `max_failures` | 連續 cycle fail，避免燒 token |
| Ring 卡 FAILED | 自動 resolve 並重試，最多 `max_failures` 次；超過才推通知退場 |
| `Ctrl+C` / `kill PID` / `pkill -f supervise.py` | 收到 SIGTERM 乾淨 kill 子程序 |

---

## 4. 即時觀察

### 看 supervisor 自己的 log

```bash
tail -f /tmp/sw_supervise.log
# 或結構化的：
tail -f orchestrator/logs/supervisor/supervise_YYYYMMDD_HHMMSS.log
```

### 看當前 agent 在做什麼

```bash
# 看現在哪一個 agent 跑著
cat orchestrator/current/heartbeat.json

# 看當前 ring 狀態（最新交棒）
tail -30 orchestrator/current/ring.md

# 看當前 agent 詳細 stdout
tail -f orchestrator/logs/$(date +%F)/*.log
```

### 一鍵掃整體進度

```bash
python sw.py progress      # ★ 總進度 % + milestones + 今日 4 agents
python sw.py status        # MAIN_ENTRY
python sw.py schedule      # cooldown / approval 狀態
```

`python sw.py progress` 輸出範例：

```
📊  SunnyWalker — Progress Snapshot
=============================================
Overall: Day 3 of 7  (2 day(s) complete)
  [████████░░░░░░░░░░░░░░░░░░░░░░]  29%

Today (Day 3):
  [A:✅] → [B:🟡] → [C:⬜] → [D:⬜]

Milestones:
  ✅  Day 1: Project skeleton, Models, Theme
  ✅  Day 2: HomeView, AlarmListView (dummy data)
  🟡  Day 3: AlarmScheduler + local notifications
  ⬜  Day 4: AudioRecorder + RecordingView
  ...

Latest D verdict: ✅  on_track  (Day 2)
Latest B build:  ⚠️  yellow  (build: pass, tests: 6 passed, lint: 1 warning)
```

---

## 5. 看完成結果

### 跑完一天看日報（2 分鐘版）

```bash
cat orchestrator/reports/daily/$(date +%F).md
```

### 看 D 的評估與明日 brief

```bash
# 在 ring 裡（Day 還沒結束時）
grep -A 30 "Verdict:" orchestrator/current/ring.md

# 在 archive 裡（Day 已結束）
cat orchestrator/archive/$(date +%Y-%m)/$(date +%F)/ring_snapshot.md
```

### 看 git 進度（每天 1 commit）

```bash
git log --oneline -10 dev/auto
git show --stat <SHA>
```

### 看週報（週日自動產，平日要手動）

```bash
python sw.py weekly
cat orchestrator/reports/weekly/$(date +%Y-W%V).md
```

---

## 6. 出事處理

### 找哪個 cycle 失敗

```bash
python sw.py fail          # 顯示最新 failure summary（含診斷提示）
ls orchestrator/logs/$(date +%F)/_failure_*.md
```

### 卡 FAILED 想繼續

```bash
# 先看為什麼掛
python sw.py fail

# 修完後
python sw.py resolve       # 清 FAILED 狀態
python sw.py next          # 重跑該 agent

# 或重啟 supervisor
nohup python supervise.py --max-days 5 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

### 想立刻停止 supervisor

```bash
pkill -f supervise.py      # 收到 SIGTERM，乾淨 kill 子程序 + log 收尾
```

### 想完全清狀態重來

```bash
bash setup_day0.sh --reset-only
```

---

## 7. 常見場景

### 出門 8 小時，期望跑完 3-4 天

```bash
nohup python supervise.py \
    --max-days 4 \
    --idle-min 20 \
    --stop-after 18:00 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

每天約 15-20 分鐘 + 20 分鐘 idle = ~40 分/天。8 小時可跑 ~12 個週期，但 `--max-days 4` 卡上限到 4 天就停。

### 過夜跑，怕影響早上工作

```bash
nohup python supervise.py \
    --max-days 7 \
    --idle-min 30 \
    --stop-after 07:00 \
    >> /tmp/sw_supervise.log 2>&1 &
disown
```

### 想精準停在 B 之後

編 `orchestrator/schedule.csv`：
```csv
weekday,start,end,stop_after,enabled
mon,00:00,23:59,B,true
...
```
然後啟 supervisor，每天 B 跑完就 approval gate 卡住，supervisor 自動 sleep 等你 `python sw.py approve`。

---

## 8. 一定要知道的事

- **supervisor 不會自動 resolve FAILED**：故意的，需要人類介入。FAILED 一律推通知
- **macOS 通知要授權**：第一次跑會跳「python 想要傳送通知」，請允許
- **Token 耗盡會自動 cooldown 4 小時**：supervisor 期間 sleep 等就好，不用手動處理
- **每天 1 commit + push**：C 會自動推到 `origin/dev/auto`，不會碰 `main`
