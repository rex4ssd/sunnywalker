"""MAIN_ENTRY.md — the resume manifest at project root.

This is the FIRST file anyone (human or AI) should read after a crash, reboot,
power-out, or coming back after vacation. It tells you exactly:
    - what project this is
    - what day we're on
    - what was the last completed agent
    - who runs next
    - where to find recent logs
    - any open blockers
"""
from __future__ import annotations
import datetime as dt

from . import heartbeat, ring, schedule
from .paths import (DAILY, LOGS, MAIN_ENTRY, PROGRESS, RING, WEEKLY)


def render(project_name: str, project_description: str = "") -> str:
    last = ring.last()
    current_day = ring.current_day()
    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")

    # Header
    lines = []
    lines.append(f"# {project_name} — Main Entry")
    lines.append("")
    if project_description:
        lines.append(f"_{project_description}_")
        lines.append("")
    lines.append(f"Last updated: **{now}**")
    lines.append("")
    lines.append("> **This is the resume manifest. After a crash / shutdown / vacation, read this file first.**")
    lines.append("")

    # Resume point
    lines.append("## ▶️  Resume point")
    if last is None:
        lines.append("- Status: **fresh** — no ring activity yet")
        lines.append("- Next: run `sw next` to start Day 1 with the Coder")
    else:
        try:
            role, day = ring.next_agent()
            letter = ring.ROLE_TO_LETTER[role]
            lines.append(f"- Current day: **{current_day}**")
            lines.append(f"- Last entry: `[{last.agent}] Day {last.day}` — `{last.status}`")
            lines.append(f"- Next up: `[{letter}] {role}` (Day {day})")
            lines.append("- Recovery command: `sw next`")
        except RuntimeError as e:
            lines.append(f"- Current day: **{current_day}**")
            lines.append(f"- Last entry: `[{last.agent}] Day {last.day}` — `{last.status}`")
            lines.append(f"- ⚠️ {e}")
            lines.append("- Recovery command: read the ring, fix, then `sw resolve` then `sw next`")
    lines.append("")

    # Schedule / cooldown / approval
    lines.append("## ⏰  Schedule, cooldown & approval")
    in_cd, until, reason = schedule.is_in_cooldown()
    if in_cd and until:
        delta = until - dt.datetime.now().astimezone()
        mins = int(delta.total_seconds() / 60)
        lines.append(f"- ⏸  **In cooldown** ({reason}) — until `{until}` (~{mins} min)")
        lines.append(f"- `sw next` will exit silently until then. Cron-safe.")
        lines.append(f"- Override: `sw clear-cooldown`")
    else:
        lines.append(f"- ✅ No active cooldown (cooldown_hours = {schedule.cooldown_hours()})")

    gated, payload = schedule.is_awaiting_approval()
    if gated:
        lines.append(f"- ⏸  **Awaiting your approval** — paused after `[{payload.get('stopped_after')}]` "
                     f"at `{payload.get('stopped_at')}`")
        lines.append(f"- Reason: {payload.get('reason')}")
        lines.append(f"- Continue: `sw approve` (then `sw next`)")
    else:
        today_stop = schedule.stop_after_for_today()
        if today_stop != "D":
            lines.append(f"- 🛑 Today's stop_after = `{today_stop}` — pipeline will pause after that agent")
        else:
            lines.append(f"- ✅ Today runs full A→B→C→D (no stop_after configured)")

    if schedule.use_csv_schedule():
        allowed, nxt = schedule.is_in_allowed_window()
        if allowed:
            lines.append("- ✅ In allowed weekday window")
        elif nxt:
            lines.append(f"- ⏸  Outside scheduled window — next: `{nxt}`")
    lines.append("")

    # Heartbeat
    lines.append("## 💓  Heartbeat (crash detection)")
    stale, hb = heartbeat.is_stale()
    if hb is None:
        lines.append("- No active heartbeat — system is idle / not running")
    else:
        alive = heartbeat.is_process_alive()
        lines.append(f"- Last orchestrator activity: {hb.get('started_at', 'unknown')}")
        lines.append(f"- Was running: `[{hb.get('agent')}]` Day {hb.get('day')} on `{hb.get('host', '?')}`")
        lines.append(f"- PID {hb.get('pid')}: {'**alive**' if alive else '**dead** (crashed or finished)'}")
        if stale and not alive:
            lines.append("- ⚠️ **Heartbeat is stale AND process is dead.** Likely crash. Run `sw recover`")
    lines.append("")

    # Recent ring (last 8 entries)
    lines.append("## 🔁  Recent ring entries (last 8)")
    ents = ring.entries()
    if not ents:
        lines.append("- (ring empty)")
    else:
        for e in ents[-8:]:
            marker = {"DONE": "✅", "IN_PROGRESS": "🟡", "FAILED": "❌",
                      "PAUSED_TOKEN_LIMIT": "⏸️"}.get(e.status, "❔")
            tail = (f"→ {e.handoff_to}" if e.handoff_to
                    else f"End Day {e.end_of_day}" if e.end_of_day
                    else "")
            lines.append(f"- {marker} `[{e.agent}]` Day {e.day:2d}  {e.timestamp}  {tail}")
    lines.append("")
    lines.append(f"Full ring: `{RING.relative_to(MAIN_ENTRY.parent)}`")
    lines.append("")

    # Recent daily reports
    lines.append("## 📋  Recent daily reports (2-min reads)")
    if DAILY.exists():
        recent = sorted(DAILY.glob("*.md"))[-7:]
        if recent:
            for f in recent:
                lines.append(f"- `{f.relative_to(MAIN_ENTRY.parent)}`")
        else:
            lines.append("- (none yet)")
    else:
        lines.append("- (none yet)")
    lines.append("")

    # Weekly
    lines.append("## 📅  Weekly reports")
    if WEEKLY.exists():
        recent = sorted(WEEKLY.glob("*.md"))[-4:]
        if recent:
            for f in recent:
                lines.append(f"- `{f.relative_to(MAIN_ENTRY.parent)}`")
        else:
            lines.append("- (run `sw weekly` to generate)")
    lines.append("")

    # Progress (live TODO)
    lines.append("## 📝  Live progress")
    if PROGRESS.exists():
        lines.append(f"- `{PROGRESS.relative_to(MAIN_ENTRY.parent)}`")
    else:
        lines.append("- (none yet)")
    lines.append("")

    # Open blockers (FAILED / PAUSED entries)
    blockers = [e for e in ents if e.status in ("FAILED", "PAUSED_TOKEN_LIMIT")]
    attn = [e for e in ents if e.human_attention]
    if blockers or attn:
        lines.append("## 🚨  Open blockers / human attention")
        for e in blockers:
            log_dir = LOGS / dt.date.today().isoformat()  # best guess
            lines.append(f"- **[{e.agent}] Day {e.day} {e.status}** — logs: `{log_dir}`")
        for e in attn:
            lines.append(f"- **[D] Day {e.day}** — {e.human_attention}")
        lines.append("")

    # Verbose log dirs (active, not yet archived)
    lines.append("## 🗂️  Active verbose logs (not yet archived)")
    if LOGS.exists():
        days = sorted([p for p in LOGS.iterdir() if p.is_dir()])[-7:]
        if days:
            for d in days:
                lines.append(f"- `{d.relative_to(MAIN_ENTRY.parent)}`")
        else:
            lines.append("- (empty)")
    lines.append("")

    return "\n".join(lines) + "\n"


def write(project_name: str, project_description: str = "") -> None:
    MAIN_ENTRY.parent.mkdir(parents=True, exist_ok=True)
    MAIN_ENTRY.write_text(render(project_name, project_description), encoding="utf-8")
