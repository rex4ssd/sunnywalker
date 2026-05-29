"""Reports & progress notes.

Three layers:
    progress.md      — live rolling TODO (overwritten daily)
    daily/YYYY-MM-DD.md — 2-minute report (auto-generated when D done)
    weekly/YYYY-Www.md  — Sunday rollup of the week

All reports are written by orchestrator after agents complete — not by the
agents themselves. They aggregate ring entries + heartbeat + lint/build stats.
"""
from __future__ import annotations
import datetime as dt
import re
from collections import defaultdict
from pathlib import Path

from . import ring
from .paths import (DAILY, PROGRESS, SNAPSHOTS, WEEKLY, today_log_dir)


# ---------- daily ----------
def write_daily(date_str: str | None = None) -> Path:
    date_str = date_str or dt.date.today().isoformat()
    # If last entry closed a day (End of Day N), report on N, not N+1
    last = ring.last()
    if last and last.end_of_day is not None:
        day_num = last.end_of_day
    else:
        day_num = ring.current_day()
    entries = [e for e in ring.entries() if e.day == day_num]

    if not entries:
        # day not in ring (probably already archived) — empty stub
        path = DAILY / f"{date_str}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"# {date_str}\n\n(no ring activity for Day {day_num})\n")
        return path

    by_agent = {e.agent: e for e in entries}
    verdict_line = _extract_verdict(by_agent.get("D"))
    tldr = _extract_tldr(by_agent.get("C")) or _extract_one_line(by_agent.get("D"))
    done_items = _extract_done(by_agent.get("A"))
    files_changed = _extract_files(by_agent.get("A"))
    build_line = _extract_build(by_agent.get("B"))
    failures = [e for e in entries if e.status == "FAILED"]
    paused = [e for e in entries if e.status == "PAUSED_TOKEN_LIMIT"]
    tomorrow = _extract_tomorrow(by_agent.get("D"))

    log_dir = today_log_dir(date_str)

    lines = []
    lines.append(f"# Day {day_num} Summary — {date_str}\n")
    lines.append(f"_2-minute report. Full ring: orchestrator/current/ring.md_\n")

    lines.append("## TL;DR")
    lines.append(tldr or "(no TL;DR available)")
    lines.append("")

    lines.append("## ✅ Done today")
    if done_items:
        lines.extend(f"- {x}" for x in done_items)
    else:
        lines.append("- (none)")
    lines.append("")

    if files_changed:
        lines.append("## Files changed")
        lines.extend(f"- `{x}`" for x in files_changed[:10])
        if len(files_changed) > 10:
            lines.append(f"- (+{len(files_changed) - 10} more)")
        lines.append("")

    lines.append("## Build & validation")
    lines.append(build_line or "- (no B entry)")
    lines.append("")

    if failures or paused:
        lines.append("## 🔥 FAILURES (read these first)")
        for e in failures + paused:
            lines.append(f"- **[{e.agent}] Day {e.day} {e.status}**")
            log_file = log_dir / f"{e.agent.lower()}_*.log"
            lines.append(f"  Full log: `{log_file}`")
            lines.append(f"  Ring entry excerpt:")
            for ln in (e.raw.strip().splitlines()[:6]):
                lines.append(f"  > {ln}")
        lines.append("")

    if tomorrow:
        lines.append("## Tomorrow")
        lines.append(tomorrow)
        lines.append("")

    lines.append("## Verdict")
    lines.append(verdict_line or "(no D entry)")
    lines.append("")

    lines.append("---")
    lines.append(f"Full verbose logs: `{log_dir}`")
    lines.append(f"Ring snapshot: `orchestrator/archive/{date_str[:7]}/{date_str}/ring_snapshot.md` (after archive)")

    path = DAILY / f"{date_str}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def _extract_one_line(e) -> str | None:
    if not e:
        return None
    # First non-empty line of the entry body
    for ln in e.raw.splitlines():
        s = ln.strip()
        if s and not s.startswith("#") and not s.startswith("Status:") and not s.startswith("Model:"):
            return s
    return None


def _extract_verdict(d_entry) -> str | None:
    if not d_entry:
        return None
    m = re.search(r"###\s*Verdict:\s*(\S+)", d_entry.raw)
    if m:
        return f"**{m.group(1)}** — see D entry"
    return None


def _extract_tldr(c_entry) -> str | None:
    if not c_entry:
        return None
    m = re.search(r"\*\*TL;DR\*\*:\s*(.+)", c_entry.raw)
    return m.group(1).strip() if m else None


def _extract_done(a_entry) -> list[str]:
    if not a_entry:
        return []
    m = re.search(r"###\s*What I did\s*\n(.+?)(?=\n###|\Z)", a_entry.raw, re.DOTALL)
    if not m:
        return []
    return [ln.lstrip("- ").strip() for ln in m.group(1).splitlines() if ln.strip().startswith("-")]


def _extract_files(a_entry) -> list[str]:
    if not a_entry:
        return []
    m = re.search(r"###\s*Files\s*\n(.+?)(?=\n###|\Z)", a_entry.raw, re.DOTALL)
    if not m:
        return []
    out = []
    for ln in m.group(1).splitlines():
        s = ln.strip()
        if s.startswith(("+", "~", "-")):
            out.append(s)
    return out


def _extract_build(b_entry) -> str | None:
    if not b_entry:
        return None
    m = re.search(r"###\s*Verdict:\s*(\S+)", b_entry.raw)
    verdict = m.group(1) if m else "?"
    pass_m = re.search(r"Build:\s*(\S+)", b_entry.raw)
    tests_m = re.search(r"Tests:\s*([^\n]+)", b_entry.raw)
    return (f"- Verdict: **{verdict}**  "
            f"Build: {pass_m.group(1) if pass_m else '?'}  "
            f"Tests: {tests_m.group(1).strip() if tests_m else '?'}")


def _extract_tomorrow(d_entry) -> str | None:
    if not d_entry:
        return None
    m = re.search(r"###\s*For next.*?\n(.+?)(?=\n→|\Z)", d_entry.raw, re.DOTALL)
    if not m:
        return None
    body = m.group(1).strip()
    # Take just the "Primary task" line if present, else first 200 chars
    pt = re.search(r"\*\*Primary task\*\*:\s*(.+)", body)
    if pt:
        return pt.group(1).strip()
    return body[:200] + ("..." if len(body) > 200 else "")


# ---------- weekly ----------
def write_weekly(today: dt.date | None = None) -> Path:
    today = today or dt.date.today()
    year, week, _ = today.isocalendar()
    monday = today - dt.timedelta(days=today.weekday())
    sunday = monday + dt.timedelta(days=6)

    daily_files = []
    for i in range(7):
        d = (monday + dt.timedelta(days=i)).isoformat()
        f = DAILY / f"{d}.md"
        if f.exists():
            daily_files.append((d, f))

    lines = [
        f"# Week {week}, {year} — {monday} to {sunday}\n",
        f"## Days completed: {len(daily_files)}/7\n",
    ]

    completed = []
    blockers_all = []
    for date_str, f in daily_files:
        txt = f.read_text(encoding="utf-8")
        tldr_m = re.search(r"## TL;DR\n(.+)", txt)
        verdict_m = re.search(r"## Verdict\n\*\*(\w+)\*\*", txt)
        completed.append((date_str,
                          tldr_m.group(1).strip() if tldr_m else "(no tldr)",
                          verdict_m.group(1) if verdict_m else "?"))
        if "🔥 FAILURES" in txt:
            blockers_all.append(date_str)

    lines.append("## Daily TL;DR")
    for d, tldr, v in completed:
        emoji = {"on_track": "✅", "at_risk": "⚠️", "off_track": "❌"}.get(v, "❔")
        lines.append(f"- {emoji} **{d}** ({v}): {tldr}")
    lines.append("")

    if blockers_all:
        lines.append("## Days with failures")
        lines.extend(f"- {d} — see `reports/daily/{d}.md`" for d in blockers_all)
        lines.append("")

    lines.append("## Pace")
    pace = "green" if len(blockers_all) == 0 else "yellow" if len(blockers_all) <= 1 else "red"
    lines.append(f"- {pace} ({len(blockers_all)} days with failures out of {len(daily_files)})")

    path = WEEKLY / f"{year}-W{week:02d}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


# ---------- progress (live TODO) ----------
def write_progress(milestones: list[dict] | None = None) -> Path:
    """Rewrite progress.md from ring history + milestones config.

    milestones: list of {"day": 1, "title": "...", "done": bool}
    """
    PROGRESS.parent.mkdir(parents=True, exist_ok=True)
    current = ring.current_day()
    all_entries = ring.entries()
    completed_days = sorted({e.day for e in all_entries
                            if e.end_of_day is not None})

    lines = [
        f"# Live Progress — last update {dt.datetime.now().astimezone().isoformat(timespec='seconds')}",
        "",
        f"Current day: **{current}**",
        "",
    ]

    if milestones:
        lines.append("## Milestones")
        for m in milestones:
            done = m["day"] in completed_days or m.get("done")
            checkbox = "[x]" if done else "[ ]"
            lines.append(f"- {checkbox} **Day {m['day']}**: {m['title']}")
        lines.append("")

    # Blockers (any FAILED still not resolved + paused)
    last = ring.last()
    if last and last.status in ("FAILED", "PAUSED_TOKEN_LIMIT"):
        lines.append("## ⚠️ Currently blocked")
        lines.append(f"- [{last.agent}] Day {last.day} — {last.status}")
        lines.append("")

    # Snapshot
    SNAPSHOTS.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text("\n".join(lines), encoding="utf-8")
    snapshot = SNAPSHOTS / f"{dt.date.today().isoformat()}.md"
    snapshot.write_text("\n".join(lines), encoding="utf-8")
    return PROGRESS
