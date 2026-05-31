"""Progress view — single-page snapshot of overall project completion.

Used by `sw progress`. Computes:
  - Overall % from completed days / max_days
  - Today's agent pipeline (A B C D done/in_progress/pending)
  - Milestone checklist (from config.yaml)
  - Latest D verdict (on_track / at_risk / off_track)
  - Latest B build/test/lint status

Pure display; reads ring + config + archive. No state mutation.
"""
from __future__ import annotations
import datetime as dt
import re
from pathlib import Path

import yaml

from . import ring
from .paths import ARCHIVE, CONFIG, DAILY


def _load_milestones() -> list[dict]:
    if not CONFIG.exists():
        return []
    try:
        cfg = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
        return cfg.get("milestones", []) or []
    except Exception:
        return []


def _completed_days() -> set[int]:
    """Days that have an `End of Day N` marker either in ring or archive."""
    done: set[int] = set()
    for e in ring.entries():
        if e.end_of_day is not None:
            done.add(e.end_of_day)
    # also scan archive snapshots
    if ARCHIVE.exists():
        for snap in ARCHIVE.rglob("ring_snapshot.md"):
            try:
                text = snap.read_text(encoding="utf-8", errors="replace")
                for m in re.finditer(r"^→ End of Day (\d+)$", text, re.MULTILINE):
                    done.add(int(m.group(1)))
            except OSError:
                pass
    return done


def _today_agents() -> dict[str, str]:
    """Return {A: status, B: status, C: status, D: status} for the current day.

    Status values: DONE / IN_PROGRESS / FAILED / PAUSED / PENDING
    """
    current = ring.current_day()
    states = {a: "PENDING" for a in ("A", "B", "C", "D")}
    for e in ring.entries():
        if e.day != current:
            continue
        if e.agent in states:
            if e.status == "DONE":
                states[e.agent] = "DONE"
            elif e.status == "IN_PROGRESS" and states[e.agent] != "DONE":
                states[e.agent] = "IN_PROGRESS"
            elif e.status == "FAILED" and states[e.agent] != "DONE":
                states[e.agent] = "FAILED"
            elif e.status == "PAUSED_TOKEN_LIMIT" and states[e.agent] != "DONE":
                states[e.agent] = "PAUSED"
    return states


def _latest_d_verdict() -> tuple[str, int] | None:
    """Find the most recent D entry's verdict + day. Scans ring + archive."""
    candidates = []
    for e in ring.entries():
        if e.agent == "D" and e.status == "DONE":
            m = re.search(r"### Verdict:\s*(\S+)", e.raw)
            if m:
                candidates.append((e.day, m.group(1), e.timestamp))
    if not candidates:
        # scan archives (latest by mtime)
        if ARCHIVE.exists():
            snaps = sorted(ARCHIVE.rglob("ring_snapshot.md"),
                          key=lambda p: p.stat().st_mtime, reverse=True)
            for snap in snaps[:3]:
                text = snap.read_text(encoding="utf-8", errors="replace")
                # find last D entry's verdict
                for m in re.finditer(
                    r"## \[D\] Day (\d+).*?### Verdict:\s*(\S+)",
                    text, re.DOTALL,
                ):
                    candidates.append((int(m.group(1)), m.group(2), ""))
                if candidates:
                    break
    if not candidates:
        return None
    # latest day wins
    candidates.sort(key=lambda x: x[0], reverse=True)
    day, verdict, _ = candidates[0]
    return (verdict, day)


def _latest_b_summary() -> dict | None:
    """Find latest B entry, extract build/test/lint."""
    candidates = []
    for e in ring.entries():
        if e.agent == "B" and e.status == "DONE":
            candidates.append(e)
    if not candidates:
        # scan archive
        if ARCHIVE.exists():
            snaps = sorted(ARCHIVE.rglob("ring_snapshot.md"),
                          key=lambda p: p.stat().st_mtime, reverse=True)
            for snap in snaps[:3]:
                text = snap.read_text(encoding="utf-8", errors="replace")
                # extract last B block
                blocks = re.findall(
                    r"(## \[B\] Day \d+.*?)(?=\n## \[|\Z)",
                    text, re.DOTALL,
                )
                if blocks:
                    return _parse_b_block(blocks[-1])
        return None
    return _parse_b_block(candidates[-1].raw)


def _parse_b_block(raw: str) -> dict:
    out = {"verdict": "?", "build": "?", "tests": "?", "lint": "?"}
    m = re.search(r"### Verdict:\s*(\S+)", raw)
    if m:
        out["verdict"] = m.group(1)
    m = re.search(r"Build:\s*([^\n]+)", raw)
    if m:
        out["build"] = m.group(1).strip()
    m = re.search(r"Tests:\s*([^\n]+)", raw)
    if m:
        out["tests"] = m.group(1).strip()
    m = re.search(r"Lint:\s*([^\n]+)", raw)
    if m:
        out["lint"] = m.group(1).strip()
    return out


# ---------- rendering ----------
AGENT_EMOJI = {
    "DONE":        "✅",
    "IN_PROGRESS": "🟡",
    "FAILED":      "❌",
    "PAUSED":      "⏸️",
    "PENDING":     "⬜",
}

VERDICT_EMOJI = {
    "on_track":  "✅",
    "at_risk":   "⚠️",
    "off_track": "❌",
}


def _progress_bar(pct: float, width: int = 30) -> str:
    filled = int(round(pct / 100 * width))
    return "█" * filled + "░" * (width - filled)


def render() -> str:
    milestones = _load_milestones()
    total_days = len(milestones) or 7
    done_days = _completed_days()
    overall_pct = (len(done_days) / total_days) * 100 if total_days else 0

    # within-day granular % — each agent done = 1/4 of the day
    today_agents = _today_agents()
    current_day = ring.current_day()
    today_done = sum(1 for s in today_agents.values() if s == "DONE")
    today_pct = (today_done / 4) * 100
    granular_pct = ((len(done_days) + today_done / 4) / total_days) * 100 if total_days else 0

    lines = []
    lines.append("=" * 60)
    lines.append("📊  SunnyWalker — Progress Snapshot")
    lines.append("=" * 60)
    lines.append("")
    lines.append(f"Overall: Day {min(current_day, total_days)} of {total_days}  "
                f"({len(done_days)} day(s) complete)")
    lines.append(f"  [{_progress_bar(overall_pct)}]  {overall_pct:.0f}%")
    if today_done > 0 and today_done < 4:
        lines.append(f"Granular (incl. today): {granular_pct:.0f}%")
    lines.append("")

    # Today's pipeline
    lines.append(f"Today (Day {current_day}):")
    flow = []
    for a in ("A", "B", "C", "D"):
        emoji = AGENT_EMOJI.get(today_agents[a], "?")
        flow.append(f"[{a}:{emoji}]")
    lines.append(f"  {' → '.join(flow)}")
    lines.append("")

    # Milestones
    lines.append("Milestones:")
    for m in milestones:
        day = m.get("day")
        title = m.get("title", "")
        if day in done_days:
            marker = "✅"
        elif day == current_day:
            if today_done == 4:
                marker = "✅"
            elif today_done > 0:
                marker = "🟡"
            else:
                marker = "▶️"
        elif day and day < current_day:
            marker = "⚠️"   # should be done but isn't (rare)
        else:
            marker = "⬜"
        lines.append(f"  {marker}  Day {day}: {title}")
    lines.append("")

    # Latest D verdict
    v = _latest_d_verdict()
    if v:
        verdict, vday = v
        emoji = VERDICT_EMOJI.get(verdict, "❔")
        lines.append(f"Latest D verdict: {emoji}  {verdict}  (Day {vday})")
    else:
        lines.append("Latest D verdict: (no D entry yet)")

    # Latest B build/test
    b = _latest_b_summary()
    if b:
        v_emoji = {"green": "✅", "yellow": "⚠️", "red": "❌"}.get(b["verdict"], "❔")
        lines.append(f"Latest B build: {v_emoji}  {b['verdict']}  "
                    f"(build: {b['build']}, tests: {b['tests']}, lint: {b['lint']})")
    lines.append("")

    # Pointers
    lines.append("More:")
    lines.append(f"  sw status       MAIN_ENTRY.md")
    lines.append(f"  sw ring         today's ring.md")
    today_daily = DAILY / f"{dt.date.today().isoformat()}.md"
    if today_daily.exists():
        lines.append(f"  cat {today_daily}   today's 2-min report")
    lines.append("=" * 60)
    return "\n".join(lines)
