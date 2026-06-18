# SunnyWalker

A voice-interactive alarm clock for 7-year-olds. iOS 17+, Swift + SwiftUI, hand-painted watercolor aesthetic. 100% offline, no ads, no tracking.

The repo also contains **`claude_loop`** — a reusable 4-agent ring framework that builds the app one day at a time. The framework is the meta-project; SunnyWalker is the first app it builds. See `orchestrator/REUSE.md` to drop it into a new project.

---

## Quick start

```bash
# One-time
pip install -e .
claude login                  # OAuth login for claude CLI (or export ANTHROPIC_API_KEY)

# Daily
sw next                       # run the next agent in the ring
sw status                     # see MAIN_ENTRY.md (resume manifest)
```

### Three equivalent ways to run

| | Command |
|---|---|
| Installed | `sw <cmd>` |
| Direct Python | `python sw.py <cmd>` |
| Module | `python -m orchestrator <cmd>` |

The legacy `./run.sh` still forwards to `sw.py` for muscle memory.

---

## The 4-agent ring

```
A Coder ─→ B Validator ─→ C Reporter+CI ─→ D Reviewer ─┐
↑                                                       │
└───────────────── End of Day ←─────────────────────────┘
```

Each agent writes one entry to `orchestrator/current/ring.md` and stamps `→ Hand off to <next>`. D closes with `→ End of Day N` and writes tomorrow's brief for A.

| | Role | Model | Cost/day est. |
|---|---|---|---|
| A | Code Swift | Sonnet 4.6 | ~$0.32 |
| B | Build + test + lint | Haiku 4.5 | ~$0.02 |
| C | Daily report + git push | Haiku 4.5 | ~$0.03 |
| D | Honest review + tomorrow's brief | Opus 4.6 | ~$1.20 |

Safety rails:
- A cannot run `git` or `xcodebuild`
- B cannot modify code
- C can only push to `dev/auto`, never `main`
- D is read-only

---

## All commands

### Daily
- `sw next` — run whoever's next per ring
- `sw today` — keep running until D closes the day
- `sw status` — show MAIN_ENTRY.md
- `sw ring` — cat the ring file
- `sw --dry-run next` — preview prompts without calling claude

### Recovery
- `sw resume` (or `recover`) — crash recovery after reboot/power loss
- `sw resolve` — clear a previous FAILED entry after fixing

### Schedule
- `sw schedule` — show cooldown + stop_after + windows
- `sw approve` — clear approval gate (continue after stop_after)
- `sw clear-cooldown` — force-clear token-limit cooldown

### Reports
- `sw daily` — regenerate today's daily report
- `sw weekly` — generate this week's weekly report
- `sw archive` — manually archive completed day's logs
- `sw refresh` — regenerate MAIN_ENTRY.md + progress.md

### Force one agent
- `sw coder | validator | reporter | reviewer`

---

## Schedule control (`orchestrator/schedule.csv`)

```csv
weekday,start,end,stop_after,enabled
mon,07:00,23:00,,true        # full day A→B→C→D
tue,07:00,23:00,B,true       # run A,B then pause for your review
wed,07:00,23:00,C,true       # run A,B,C then pause
thu,off,off,,false           # skip day entirely
fri,07:00,23:00,,true
sat,09:00,22:00,,true
sun,09:00,22:00,,false
```

`stop_after`: A / B / C / D / empty (=D, full day). When the pipeline finishes
the agent matching `stop_after`, it writes `current/approval.json` and exits.
The next `sw next` exits silently until you run `sw approve`.

To activate the CSV schedule, set in `orchestrator/schedule.ini`:
```ini
[general]
use_schedule_csv = true
```

---

## Cron-friendly

`sw next` exits **0** when it can't run (cooldown / approval pending / off
hours). Safe to schedule:

```cron
*/30 * * * * cd /Users/lion/Documents/SunnyWalker && /usr/local/bin/sw next >> /tmp/sw.log 2>&1
```

---

## Failure handling

| Situation | Detected by | Auto action | You do |
|---|---|---|---|
| Token limit | log contains "rate limit" / "429" / "quota" | cooldown 4h (configurable), macOS notification | wait, or `sw clear-cooldown` |
| Build broken | B's verdict = red | C commits anyway with `[BROKEN]` prefix, D evaluates | fix per D's brief |
| Crash / power-out | heartbeat stale + PID dead | `sw resume` marks FAILED, notifies | read log, fix, `sw resolve` |
| Stop_after reached | post-agent check | approval gate + notification | review, `sw approve` |
| D flags `🚨 HUMAN ATTENTION` | parse ring | surface in MAIN_ENTRY + notification | act on the issue |

All failures write the **full log path** into the daily report so you can
`open` it directly.

---

## File layout

```
SunnyWalker/
├── MAIN_ENTRY.md                ★ resume manifest (read first)
├── sw.py                        ★ Python entry point
├── pyproject.toml               package metadata
├── run.sh                       legacy bash shim → sw.py
│
├── docs/
│   ├── swift_native_spec.md     iOS spec
│   ├── first_idea.md            original concept
│   └── multi_agent_workflow.md  framework design
│
├── scripts/                     project-specific helpers
│   ├── validate.sh              run by AI B
│   ├── git_ca.sh                run by AI C
│   └── dev.sh                   you use directly
│
├── tests/                       pytest suite (39 tests)
│
└── orchestrator/                claude_loop framework
    ├── __init__.py / __main__.py
    ├── orchestrator.py          thin driver
    ├── config.yaml              ← change this per project
    ├── schedule.ini             cooldown settings
    ├── schedule.csv             weekday windows + stop_after
    ├── REUSE.md                 how to clone to another project
    ├── prompts/                 4 agent role prompts
    ├── lib/                     reusable code
    │   ├── ring.py              baton parser
    │   ├── heartbeat.py         crash detection
    │   ├── schedule.py          cooldown + approval
    │   ├── notify.py            macOS notifications
    │   ├── archive.py           cold storage
    │   ├── reports.py           daily/weekly/progress
    │   └── main_entry.py        manifest renderer
    │
    ├── current/                 active state
    │   ├── ring.md              today's baton
    │   ├── heartbeat.json       liveness
    │   ├── paused_until.json    cooldown end
    │   └── approval.json        review gate
    ├── reports/
    │   ├── daily/YYYY-MM-DD.md
    │   └── weekly/YYYY-Www.md
    ├── progress/
    │   ├── progress.md          live TODO
    │   └── snapshots/
    ├── logs/YYYY-MM-DD/         verbose claude transcripts
    └── archive/YYYY-MM/         post-success cold storage
```

---

## Run tests

```bash
pip install -e ".[dev]"
pytest tests/ -v
```

39 tests cover ring parsing, schedule/cooldown/approval, report generation,
MAIN_ENTRY rendering, and token-limit detection.

---

## Reusing the framework

See `orchestrator/REUSE.md`. Short version:

```bash
cp -r SunnyWalker/orchestrator   my_new_project/orchestrator
cp    SunnyWalker/sw.py           my_new_project/sw.py
cp    SunnyWalker/pyproject.toml  my_new_project/pyproject.toml
cd my_new_project
# Edit orchestrator/config.yaml (project name + spec_path)
# Replace scripts/validate.sh with your project's validator
pip install -e .
sw next
```
