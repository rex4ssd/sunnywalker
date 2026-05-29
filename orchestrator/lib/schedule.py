"""Scheduling — cooldown after token limit + optional weekday windows.

Two config files, both in `orchestrator/`:

    schedule.ini    — global settings (cooldown hours, max retries, csv toggle)
    schedule.csv    — optional per-weekday allowed run windows

Runtime state:

    current/paused_until.json   — cooldown end time + reason

The orchestrator calls `can_run_now()` before spawning any agent. If false,
it prints the reason + next allowed time and exits 0 (so cron is happy).

When token limit is detected (looks_like_token_limit), the orchestrator calls
`mark_token_paused()` which writes `paused_until.json` with `now + cooldown_h`.
"""
from __future__ import annotations
import configparser
import csv
import datetime as dt
import json
from pathlib import Path

from .paths import CURRENT, ORCH

SCHEDULE_INI  = ORCH / "schedule.ini"
SCHEDULE_CSV  = ORCH / "schedule.csv"
PAUSED_UNTIL  = CURRENT / "paused_until.json"
APPROVAL      = CURRENT / "approval.json"

DEFAULT_INI = """# claude_loop schedule settings.
# Edit these freely; orchestrator reads fresh on each call.

[token_limit]
# After detecting AI token / rate-limit / quota-exhausted error in agent log,
# wait this many hours before the pipeline will run again.
cooldown_hours = 4.0

# Stop running entirely after this many consecutive token failures (humans intervene).
max_consecutive_failures = 3

[general]
# If true, ALSO enforce schedule.csv weekday windows (work hours only, etc.).
use_schedule_csv = false

# If true, write a small note to MAIN_ENTRY.md whenever cooldown triggers.
note_in_main_entry = true
"""

DEFAULT_CSV = """# weekday,start,end,stop_after,enabled
#
# stop_after:  A | B | C | D | (empty = full day, same as D)
#              After this agent finishes for the day, pipeline pauses.
#              You review the output, then run `sw approve` to continue.
# enabled:     true / false   (false = skip this weekday entirely)
weekday,start,end,stop_after,enabled
mon,07:00,23:00,,true
tue,07:00,23:00,,true
wed,07:00,23:00,,true
thu,07:00,23:00,,true
fri,07:00,23:00,,true
sat,09:00,22:00,B,true
sun,09:00,22:00,,false
"""

WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
VALID_STOP = {"A", "B", "C", "D"}


# ---------- config loaders ----------
def ensure_files() -> None:
    SCHEDULE_INI.parent.mkdir(parents=True, exist_ok=True)
    if not SCHEDULE_INI.exists():
        SCHEDULE_INI.write_text(DEFAULT_INI, encoding="utf-8")
    if not SCHEDULE_CSV.exists():
        SCHEDULE_CSV.write_text(DEFAULT_CSV, encoding="utf-8")


def _ini() -> configparser.ConfigParser:
    ensure_files()
    cp = configparser.ConfigParser()
    cp.read(SCHEDULE_INI, encoding="utf-8")
    return cp


def cooldown_hours() -> float:
    return _ini().getfloat("token_limit", "cooldown_hours", fallback=4.0)


def max_consecutive_failures() -> int:
    return _ini().getint("token_limit", "max_consecutive_failures", fallback=3)


def use_csv_schedule() -> bool:
    return _ini().getboolean("general", "use_schedule_csv", fallback=False)


def note_in_main_entry() -> bool:
    return _ini().getboolean("general", "note_in_main_entry", fallback=True)


# ---------- paused_until state ----------
def mark_token_paused(reason: str = "token_limit",
                     hours: float | None = None) -> dt.datetime:
    """Write paused_until.json. Returns the cooldown-end timestamp."""
    h = hours if hours is not None else cooldown_hours()
    until = dt.datetime.now().astimezone() + dt.timedelta(hours=h)
    PAUSED_UNTIL.parent.mkdir(parents=True, exist_ok=True)
    PAUSED_UNTIL.write_text(json.dumps({
        "paused_until": until.isoformat(sep=" ", timespec="seconds"),
        "reason": reason,
        "cooldown_hours": h,
        "set_at": dt.datetime.now().astimezone().isoformat(sep=" ", timespec="seconds"),
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    return until


def read_paused_until() -> tuple[dt.datetime | None, str]:
    if not PAUSED_UNTIL.exists():
        return (None, "")
    try:
        d = json.loads(PAUSED_UNTIL.read_text())
        if not d:
            return (None, "")
        until = dt.datetime.fromisoformat(d["paused_until"])
        return (until, d.get("reason", ""))
    except (json.JSONDecodeError, KeyError, ValueError):
        return (None, "")


def clear_cooldown() -> None:
    if not PAUSED_UNTIL.exists():
        return
    try:
        PAUSED_UNTIL.unlink()
    except (PermissionError, OSError):
        try:
            PAUSED_UNTIL.write_text("{}")
        except OSError:
            pass


def is_in_cooldown(now: dt.datetime | None = None
                  ) -> tuple[bool, dt.datetime | None, str]:
    """Return (active, until, reason). Auto-clears expired cooldown files."""
    until, reason = read_paused_until()
    if until is None:
        return (False, None, "")
    now = now or dt.datetime.now().astimezone()
    if now < until:
        return (True, until, reason)
    # expired — clean up
    clear_cooldown()
    return (False, until, reason)


# ---------- weekday windows ----------
def load_csv_windows() -> dict[str, dict]:
    """Return {weekday: {start, end, stop_after, enabled}} from schedule.csv.

    Comment lines (starting with #) are skipped. Invalid rows are ignored.
    """
    ensure_files()
    out: dict[str, dict] = {}
    with SCHEDULE_CSV.open(encoding="utf-8") as f:
        # Strip comment lines before passing to DictReader
        lines = [ln for ln in f if not ln.lstrip().startswith("#")]
    reader = csv.DictReader(lines)
    for row in reader:
        wd = (row.get("weekday") or "").strip().lower()
        if wd not in WEEKDAYS:
            continue
        try:
            start = dt.time.fromisoformat((row.get("start") or "00:00").strip())
            end   = dt.time.fromisoformat((row.get("end")   or "23:59").strip())
        except ValueError:
            continue
        en = (row.get("enabled") or "true").strip().lower() in ("true", "1", "yes", "y")
        stop = (row.get("stop_after") or "").strip().upper()
        if stop and stop not in VALID_STOP:
            stop = ""
        out[wd] = {"start": start, "end": end, "stop_after": stop or "D", "enabled": en}
    return out


def stop_after_for_today(now: dt.datetime | None = None) -> str:
    """Return the agent letter (A/B/C/D) after which we pause for human review."""
    if not use_csv_schedule():
        return "D"
    now = now or dt.datetime.now().astimezone()
    windows = load_csv_windows()
    today = WEEKDAYS[now.weekday()]
    if today not in windows:
        return "D"
    return windows[today]["stop_after"]


def is_in_allowed_window(now: dt.datetime | None = None
                        ) -> tuple[bool, dt.datetime | None]:
    """Return (allowed_now, next_window_start_if_not)."""
    if not use_csv_schedule():
        return (True, None)
    now = now or dt.datetime.now().astimezone()
    windows = load_csv_windows()
    today = WEEKDAYS[now.weekday()]
    if today in windows:
        w = windows[today]
        if w["enabled"] and w["start"] <= now.time() <= w["end"]:
            return (True, None)
    # Search forward for the next enabled window
    for delta in range(1, 8):
        future = now + dt.timedelta(days=delta)
        wd = WEEKDAYS[future.weekday()]
        if wd in windows:
            w = windows[wd]
            if w["enabled"]:
                nxt = future.replace(hour=w["start"].hour, minute=w["start"].minute,
                                     second=0, microsecond=0)
                return (False, nxt)
    return (False, None)


# ---------- approval gate (after stop_after agent runs) ----------
def mark_awaiting_approval(stopped_after: str, reason: str = "stop_after reached") -> None:
    APPROVAL.parent.mkdir(parents=True, exist_ok=True)
    APPROVAL.write_text(json.dumps({
        "date": dt.date.today().isoformat(),
        "stopped_after": stopped_after,
        "stopped_at": dt.datetime.now().astimezone().isoformat(sep=" ", timespec="seconds"),
        "reason": reason,
    }, indent=2, ensure_ascii=False), encoding="utf-8")


def is_awaiting_approval(now: dt.datetime | None = None
                        ) -> tuple[bool, dict | None]:
    """Return (gated, payload). Payload has date/stopped_after/reason."""
    if not APPROVAL.exists():
        return (False, None)
    try:
        d = json.loads(APPROVAL.read_text())
        if not d:
            return (False, None)
    except json.JSONDecodeError:
        return (False, None)
    # Stale approval (from previous day) auto-clears
    today = (now or dt.datetime.now().astimezone()).date().isoformat()
    if d.get("date") != today:
        clear_approval()
        return (False, None)
    return (True, d)


def clear_approval() -> None:
    if not APPROVAL.exists():
        return
    try:
        APPROVAL.unlink()
    except (PermissionError, OSError):
        try:
            APPROVAL.write_text("{}")
        except OSError:
            pass


# ---------- combined gate ----------
def can_run_now(now: dt.datetime | None = None
               ) -> tuple[bool, str, dt.datetime | None]:
    """Single decision point. Returns (allowed, reason, next_allowed_time)."""
    in_cd, cd_until, cd_reason = is_in_cooldown(now)
    if in_cd:
        return (False, f"cooldown ({cd_reason})", cd_until)
    gated, payload = is_awaiting_approval(now)
    if gated:
        return (False,
                f"awaiting your approval (stopped after {payload.get('stopped_after')}, "
                f"run `sw approve` to continue)",
                None)
    allowed, next_start = is_in_allowed_window(now)
    if not allowed:
        return (False, "outside scheduled window", next_start)
    return (True, "", None)


def status_summary() -> str:
    """Multi-line human-readable status — used by `sw schedule` and MAIN_ENTRY."""
    lines = []
    lines.append(f"cooldown_hours = {cooldown_hours()}")
    lines.append(f"max_consecutive_failures = {max_consecutive_failures()}")
    lines.append(f"use_schedule_csv = {use_csv_schedule()}")
    lines.append(f"stop_after (today) = {stop_after_for_today()}")
    lines.append("")
    in_cd, until, reason = is_in_cooldown()
    if in_cd and until:
        delta = until - dt.datetime.now().astimezone()
        mins = int(delta.total_seconds() / 60)
        lines.append(f"⏸  In cooldown ({reason}) — until {until} (~{mins} min)")
    else:
        lines.append("✅ No active cooldown")
    gated, payload = is_awaiting_approval()
    if gated:
        lines.append(f"⏸  Awaiting approval — stopped after [{payload.get('stopped_after')}] "
                     f"at {payload.get('stopped_at')}")
        lines.append("   Run `sw approve` to continue (or `sw clear-approval` for same effect).")
    else:
        lines.append("✅ No approval pending")
    if use_csv_schedule():
        allowed, nxt = is_in_allowed_window()
        if allowed:
            lines.append("✅ In allowed weekday window")
        elif nxt:
            lines.append(f"⏸  Outside window — next: {nxt}")
        else:
            lines.append("⏸  Outside window (no future window found)")
    return "\n".join(lines)
