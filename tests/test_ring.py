"""Ring parser + state transitions."""
import datetime as dt

import pytest

from orchestrator.lib import ring, paths


def _append(text: str) -> None:
    with paths.RING.open("a", encoding="utf-8") as f:
        f.write(text)


def _entry(letter: str, day: int, status: str, tail: str = "") -> str:
    ts = ring._now_ts()
    return (f"\n## [{letter}] Day {day} — {ts}\n"
            f"Status: {status}\n"
            f"Model:  test\n\n"
            f"### What I did\n- something\n\n"
            f"{tail}\n")


# ---------- next_agent across states ----------
def test_empty_ring_starts_with_coder_day1():
    assert ring.next_agent() == ("coder", 1)


def test_after_a_hands_off_to_b():
    _append(_entry("A", 1, "DONE", "→ Hand off to B"))
    assert ring.next_agent() == ("validator", 1)


def test_after_b_hands_off_to_c():
    _append(_entry("A", 1, "DONE", "→ Hand off to B"))
    _append(_entry("B", 1, "DONE", "→ Hand off to C"))
    assert ring.next_agent() == ("reporter", 1)


def test_after_end_of_day_rolls_over_to_next_day_a():
    _append(_entry("A", 1, "DONE", "→ Hand off to B"))
    _append(_entry("B", 1, "DONE", "→ Hand off to C"))
    _append(_entry("C", 1, "DONE", "→ Hand off to D"))
    _append(_entry("D", 1, "DONE", "→ End of Day 1"))
    assert ring.next_agent() == ("coder", 2)


def test_failed_status_raises_runtime_error():
    _append(_entry("B", 1, "FAILED"))
    with pytest.raises(RuntimeError, match="FAILED"):
        ring.next_agent()


def test_in_progress_returns_same_agent():
    _append(_entry("A", 1, "IN_PROGRESS"))
    assert ring.next_agent() == ("coder", 1)


# ---------- mark_resolved ----------
def test_mark_resolved_allows_retry():
    _append(_entry("B", 1, "FAILED"))
    ring.mark_resolved()
    assert ring.next_agent() == ("validator", 1)


def test_mark_resolved_without_failed_raises():
    _append(_entry("A", 1, "DONE", "→ Hand off to B"))
    with pytest.raises(RuntimeError, match="No FAILED"):
        ring.mark_resolved()


# ---------- timestamp formats ----------
def test_parser_accepts_T_separator_iso_timestamp():
    """Old isoformat used T separator. Parser should accept."""
    with paths.RING.open("a", encoding="utf-8") as f:
        f.write("\n## [A] Day 1 — 2026-05-29T12:00:00+08:00\nStatus: DONE\n\n→ Hand off to B\n")
    assert ring.next_agent() == ("validator", 1)


def test_parser_accepts_space_separator_timestamp():
    with paths.RING.open("a", encoding="utf-8") as f:
        f.write("\n## [A] Day 1 — 2026-05-29 12:00:00+08:00\nStatus: DONE\n\n→ Hand off to B\n")
    assert ring.next_agent() == ("validator", 1)


# ---------- human_attention parsing ----------
def test_d_entry_with_human_attention():
    eod = _entry("D", 1, "DONE", "→ End of Day 1\n🚨 HUMAN ATTENTION: build broken")
    _append(eod)
    last = ring.last()
    assert last.human_attention == "build broken"


# ---------- rotation ----------
def test_rotate_keeps_only_eod_entry(tmp_path):
    _append(_entry("A", 1, "DONE", "→ Hand off to B"))
    _append(_entry("B", 1, "DONE", "→ Hand off to C"))
    _append(_entry("C", 1, "DONE", "→ Hand off to D"))
    _append(_entry("D", 1, "DONE", "→ End of Day 1"))
    snapshot = tmp_path / "snap.md"
    ring.rotate_after_day(1, snapshot)
    assert snapshot.exists()
    remaining = ring.entries()
    assert len(remaining) == 1
    assert remaining[0].agent == "D"
    assert remaining[0].end_of_day == 1
