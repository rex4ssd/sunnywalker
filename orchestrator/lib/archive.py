"""Archive — when a day completes successfully, cold-store its verbose logs.

After D's `→ End of Day N` appears AND the daily report is generated:
    1. Snapshot ring -> archive/<YYYY-MM>/<DATE>/ring_snapshot.md
    2. Move logs/<DATE>/* -> archive/<YYYY-MM>/<DATE>/logs/
    3. Trim ring to keep only D's closing entry (so tomorrow's A can read it)
"""
from __future__ import annotations
import shutil
from pathlib import Path

from . import ring
from .paths import LOGS, archive_dir_for, today_log_dir


def archive_day(date_str: str, day: int) -> Path:
    """Snapshot ring + move logs into archive. Returns archive root."""
    target = archive_dir_for(date_str)
    target.mkdir(parents=True, exist_ok=True)

    # 1. Snapshot ring before rotation
    snapshot = target / "ring_snapshot.md"
    ring.rotate_after_day(day, snapshot)

    # 2. Move verbose logs from logs/<date> to archive
    src = LOGS / date_str
    if src.exists():
        dest = target / "logs"
        dest.mkdir(parents=True, exist_ok=True)
        for child in src.iterdir():
            shutil.move(str(child), str(dest / child.name))
        # Try to remove empty source folder
        try:
            src.rmdir()
        except OSError:
            pass

    return target


def restore_day(date_str: str) -> None:
    """Reverse of archive_day. For debugging / re-runs."""
    target = archive_dir_for(date_str)
    if not target.exists():
        raise FileNotFoundError(target)
    log_back = today_log_dir(date_str)
    for child in (target / "logs").iterdir():
        shutil.move(str(child), str(log_back / child.name))
