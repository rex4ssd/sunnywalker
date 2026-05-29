"""pytest config — make orchestrator package importable + provide fixtures."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import pytest

from orchestrator.lib import paths, ring, schedule, heartbeat


@pytest.fixture(scope="session", autouse=True)
def _protect_user_state():
    """After the whole test session, regenerate MAIN_ENTRY.md and reset ring.md
    from the real config.yaml. Prevents tests polluting project state."""
    yield
    try:
        import yaml
        from orchestrator.lib import main_entry
        cfg_path = paths.ORCH / "config.yaml"
        if cfg_path.exists():
            cfg = yaml.safe_load(cfg_path.read_text())
            proj = cfg.get("project", {})
            main_entry.write(proj.get("name", paths.ROOT.name),
                             proj.get("description", ""))
    except Exception:
        pass
    # Reset ring to fresh header (tests dirty it)
    try:
        paths.RING.write_text(ring.RING_HEADER, encoding="utf-8")
    except OSError:
        pass


@pytest.fixture(autouse=True)
def _reset_state():
    """Reset transient state files before each test."""
    paths.ensure_dirs()
    paths.RING.write_text(ring.RING_HEADER, encoding="utf-8")
    heartbeat.clear()
    schedule.clear_cooldown()
    schedule.clear_approval()
    yield
    heartbeat.clear()
    schedule.clear_cooldown()
    schedule.clear_approval()
