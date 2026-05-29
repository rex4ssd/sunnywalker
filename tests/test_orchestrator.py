"""Orchestrator integration: token-limit detection, dry-run, MAIN_ENTRY."""
from pathlib import Path

from orchestrator import orchestrator as orch
from orchestrator.lib import main_entry, paths, schedule


def test_token_limit_detection_in_log(tmp_path: Path):
    log = tmp_path / "fake.log"
    log.write_text("starting agent\nERROR: rate limit exceeded\nbye")
    assert orch.looks_like_token_limit(log)


def test_token_limit_negative_case(tmp_path: Path):
    log = tmp_path / "fake.log"
    log.write_text("starting agent\nall good\nbye")
    assert not orch.looks_like_token_limit(log)


def test_token_limit_matches_429(tmp_path: Path):
    log = tmp_path / "fake.log"
    log.write_text("HTTP 429 too many requests\n")
    assert orch.looks_like_token_limit(log)


def test_token_limit_matches_quota(tmp_path: Path):
    log = tmp_path / "fake.log"
    log.write_text("error: insufficient_quota\n")
    assert orch.looks_like_token_limit(log)


def test_main_entry_render_runs_clean():
    """Smoke test — MAIN_ENTRY rendering should never crash."""
    main_entry.write("TestProject", "test description")
    text = paths.MAIN_ENTRY.read_text()
    assert "TestProject" in text
    assert "Resume point" in text


def test_main_entry_shows_cooldown():
    schedule.mark_token_paused("test")
    main_entry.write("TestProject", "x")
    text = paths.MAIN_ENTRY.read_text()
    assert "In cooldown" in text


def test_main_entry_shows_approval_gate():
    schedule.mark_awaiting_approval("B", "stop_after=B")
    main_entry.write("TestProject", "x")
    text = paths.MAIN_ENTRY.read_text()
    assert "Awaiting your approval" in text or "approval" in text.lower()
