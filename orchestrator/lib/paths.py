"""Single source of truth for all framework paths.

Layout (relative to project root):

    <PROJECT_ROOT>/
    ├── MAIN_ENTRY.md                     # ★ resume manifest (root level on purpose)
    ├── orchestrator/                     # claude_loop framework (rename optional)
    │   ├── config.yaml                   # project-specific
    │   ├── orchestrator.py
    │   ├── lib/                          # reusable code
    │   ├── prompts/                      # 4 role prompts
    │   ├── current/                      # active state
    │   │   ├── ring.md                   # baton (today's cycle only)
    │   │   └── heartbeat.json            # liveness probe
    │   ├── reports/
    │   │   ├── daily/YYYY-MM-DD.md       # 2-min daily report
    │   │   └── weekly/YYYY-Www.md
    │   ├── progress/
    │   │   ├── progress.md               # live TODO (overwritten)
    │   │   └── snapshots/YYYY-MM-DD.md   # daily frozen copy
    │   ├── logs/YYYY-MM-DD/              # verbose claude transcripts (active)
    │   └── archive/YYYY-MM/YYYY-MM-DD/   # post-success cold storage
"""
from __future__ import annotations
from pathlib import Path

# Project root is two levels up from this file:
# .../<PROJECT>/orchestrator/lib/paths.py  ->  <PROJECT>
ROOT = Path(__file__).resolve().parents[2]
ORCH = ROOT / "orchestrator"

# Active / framework
CONFIG       = ORCH / "config.yaml"
LIB          = ORCH / "lib"
PROMPTS      = ORCH / "prompts"

# State (always current)
MAIN_ENTRY   = ROOT / "MAIN_ENTRY.md"          # ★ resume point at root
CURRENT      = ORCH / "current"
RING         = CURRENT / "ring.md"
HEARTBEAT    = CURRENT / "heartbeat.json"

# Reports & progress
REPORTS      = ORCH / "reports"
DAILY        = REPORTS / "daily"
WEEKLY       = REPORTS / "weekly"
PROGRESS_DIR = ORCH / "progress"
PROGRESS     = PROGRESS_DIR / "progress.md"
SNAPSHOTS    = PROGRESS_DIR / "snapshots"

# Verbose logs (cold archived after day completes)
LOGS         = ORCH / "logs"
ARCHIVE      = ORCH / "archive"


def ensure_dirs() -> None:
    """Create all framework directories if missing."""
    for p in [CURRENT, DAILY, WEEKLY, SNAPSHOTS, LOGS, ARCHIVE,
              PROMPTS, LIB]:
        p.mkdir(parents=True, exist_ok=True)


def today_log_dir(date_str: str | None = None) -> Path:
    import datetime as dt
    d = date_str or dt.date.today().isoformat()
    p = LOGS / d
    p.mkdir(parents=True, exist_ok=True)
    return p


def daily_report_path(date_str: str | None = None) -> Path:
    import datetime as dt
    d = date_str or dt.date.today().isoformat()
    return DAILY / f"{d}.md"


def archive_dir_for(date_str: str) -> Path:
    """archive/YYYY-MM/YYYY-MM-DD/ for the given date."""
    month = date_str[:7]
    return ARCHIVE / month / date_str
