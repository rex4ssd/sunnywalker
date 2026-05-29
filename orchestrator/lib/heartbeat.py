"""Heartbeat — crash / power-outage recovery.

orchestrator writes heartbeat.json every time it starts an agent. If the
process dies (kill / shutdown / crash), the heartbeat file remains stale.
On next boot, orchestrator reads heartbeat and decides:
    fresh    -> normal flow
    stale    -> last agent likely crashed; surface to user / auto-resume
"""
from __future__ import annotations
import datetime as dt
import json
import os
from pathlib import Path

from .paths import HEARTBEAT

STALE_THRESHOLD_S = 2 * 60 * 60   # 2 hours


def write(agent: str, day: int, log_path: Path, pid: int | None = None) -> None:
    HEARTBEAT.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "agent": agent,
        "day": day,
        "pid": pid or os.getpid(),
        "log_path": str(log_path),
        "started_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "host": os.uname().nodename,
    }
    HEARTBEAT.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def clear() -> None:
    if not HEARTBEAT.exists():
        return
    try:
        HEARTBEAT.unlink()
    except (PermissionError, OSError):
        # On some filesystems unlink may be denied; overwrite with empty JSON
        # so is_stale / read return None.
        try:
            HEARTBEAT.write_text("{}")
        except OSError:
            pass


def read() -> dict | None:
    if not HEARTBEAT.exists():
        return None
    try:
        data = json.loads(HEARTBEAT.read_text())
        # treat empty {} as "cleared" (cf. clear() fallback)
        return data if data else None
    except json.JSONDecodeError:
        return None


def is_stale(now: dt.datetime | None = None) -> tuple[bool, dict | None]:
    """Return (stale, heartbeat_data).

    Stale = heartbeat exists AND started_at older than threshold.
    """
    h = read()
    if h is None:
        return (False, None)
    now = now or dt.datetime.now().astimezone()
    try:
        started = dt.datetime.fromisoformat(h["started_at"])
    except (ValueError, KeyError):
        return (True, h)
    age = (now - started).total_seconds()
    return (age > STALE_THRESHOLD_S, h)


def is_process_alive() -> bool:
    """Is the PID in the heartbeat still running?"""
    h = read()
    if h is None or "pid" not in h:
        return False
    try:
        os.kill(h["pid"], 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False
