"""pytest config — make orchestrator package importable + provide fixtures."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import pytest

from orchestrator.lib import paths, ring, schedule, heartbeat


@pytest.fixture(autouse=True)
def _reset_state():
    """Reset all state files before each test."""
    paths.ensure_dirs()
    paths.RING.write_text(ring.RING_HEADER, encoding="utf-8")
    heartbeat.clear()
    schedule.clear_cooldown()
    schedule.clear_approval()
    yield
    # cleanup after
    heartbeat.clear()
    schedule.clear_cooldown()
    schedule.clear_approval()
