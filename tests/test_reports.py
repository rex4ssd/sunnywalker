"""Daily / weekly / progress report generation."""
import datetime as dt

import pytest

from orchestrator.lib import paths, reports, ring


def _setup_full_day(day: int = 1) -> None:
    """Build a complete ring with A/B/C/D entries for the given day."""
    ts = ring._now_ts()
    with paths.RING.open("a", encoding="utf-8") as f:
        f.write(f"""
## [A] Day {day} — {ts}
Status: DONE
Model:  sonnet

### What I did
- Created HomeView.swift
- Created Alarm.swift

### Files
+ SunnyWalker/HomeView.swift
+ SunnyWalker/Alarm.swift

### For next (B — Validator)
Run validate

→ Hand off to B

## [B] Day {day} — {ts}
Status: DONE
Model:  haiku

### What I did
- ran validate
- Build: pass
- Tests: 5 passed, 0 failed

### Verdict: green

### For next (C — Reporter)
green

→ Hand off to C

## [C] Day {day} — {ts}
Status: DONE
Model:  haiku

### Daily report

**TL;DR**: Day {day} skeleton complete, build passes.

→ Hand off to D

## [D] Day {day} — {ts}
Status: DONE
Model:  opus

### Verdict: on_track
Completion: 14%

Day {day} went well.

### For next (A — Coder)

**Primary task**: Build AlarmListView

→ End of Day {day}
""")


def test_write_daily_after_full_day():
    _setup_full_day(1)
    path = reports.write_daily()
    text = path.read_text()
    assert f"Day 1" in text
    assert "on_track" in text
    assert "HomeView" in text
    assert "skeleton complete" in text


def test_write_daily_includes_failures():
    ts = ring._now_ts()
    with paths.RING.open("a", encoding="utf-8") as f:
        f.write(f"\n## [A] Day 1 — {ts}\nStatus: DONE\n\n→ Hand off to B\n")
        f.write(f"\n## [B] Day 1 — {ts}\nStatus: FAILED\n\n### Reason\nbuild broken\n"
                f"\n### Full log\n`/path/to/log`\n")
    path = reports.write_daily()
    text = path.read_text()
    assert "FAILURES" in text or "FAILED" in text


def test_write_progress_with_milestones():
    _setup_full_day(1)
    progress_path = reports.write_progress([
        {"day": 1, "title": "Skeleton"},
        {"day": 2, "title": "Home view"},
        {"day": 3, "title": "Notifications"},
    ])
    text = progress_path.read_text()
    assert "[x] **Day 1**" in text  # done
    assert "[ ] **Day 2**" in text  # not done


def test_write_weekly_lists_daily_reports():
    _setup_full_day(1)
    reports.write_daily()
    weekly_path = reports.write_weekly()
    text = weekly_path.read_text()
    assert "Week" in text
    assert "Days completed" in text


def test_daily_extracts_files_from_a_entry():
    _setup_full_day(1)
    text = reports.write_daily().read_text()
    assert "HomeView.swift" in text
