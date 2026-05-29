"""Cooldown + approval + weekday windows."""
import datetime as dt
import json

import pytest

from orchestrator.lib import schedule


# ---------- cooldown ----------
def test_fresh_state_can_run():
    ok, reason, _ = schedule.can_run_now()
    assert ok, reason


def test_mark_token_paused_blocks_run():
    schedule.mark_token_paused("token_limit")
    ok, reason, until = schedule.can_run_now()
    assert not ok
    assert "cooldown" in reason
    assert until is not None


def test_default_cooldown_is_4h():
    until = schedule.mark_token_paused("test")
    delta_h = (until - dt.datetime.now().astimezone()).total_seconds() / 3600
    assert 3.95 <= delta_h <= 4.05


def test_explicit_cooldown_hours():
    until = schedule.mark_token_paused("test", hours=2.5)
    delta_h = (until - dt.datetime.now().astimezone()).total_seconds() / 3600
    assert 2.45 <= delta_h <= 2.55


def test_expired_cooldown_auto_clears():
    past = dt.datetime.now().astimezone() - dt.timedelta(hours=1)
    schedule.PAUSED_UNTIL.write_text(json.dumps({
        "paused_until": past.isoformat(sep=" ", timespec="seconds"),
        "reason": "test",
        "cooldown_hours": 4.0,
        "set_at": past.isoformat(sep=" ", timespec="seconds"),
    }))
    ok, _, _ = schedule.can_run_now()
    assert ok


def test_clear_cooldown():
    schedule.mark_token_paused("test")
    schedule.clear_cooldown()
    ok, _, _ = schedule.can_run_now()
    assert ok


# ---------- approval gate ----------
def test_no_approval_pending_initially():
    gated, _ = schedule.is_awaiting_approval()
    assert not gated


def test_mark_awaiting_approval_blocks_run():
    schedule.mark_awaiting_approval("B", "test stop_after")
    ok, reason, _ = schedule.can_run_now()
    assert not ok
    assert "approval" in reason


def test_clear_approval_allows_run():
    schedule.mark_awaiting_approval("B")
    schedule.clear_approval()
    ok, _, _ = schedule.can_run_now()
    assert ok


def test_approval_from_previous_day_auto_clears():
    yesterday = (dt.date.today() - dt.timedelta(days=1)).isoformat()
    schedule.APPROVAL.write_text(json.dumps({
        "date": yesterday,
        "stopped_after": "B",
        "stopped_at": yesterday + "T15:00:00+08:00",
        "reason": "test",
    }))
    gated, _ = schedule.is_awaiting_approval()
    assert not gated


# ---------- weekday windows ----------
def test_csv_disabled_means_always_allowed():
    # default ini has use_schedule_csv = false
    allowed, _ = schedule.is_in_allowed_window()
    assert allowed


def test_csv_enabled_with_off_day():
    schedule.SCHEDULE_INI.write_text(
        schedule.DEFAULT_INI.replace("use_schedule_csv = false",
                                     "use_schedule_csv = true"))
    schedule.SCHEDULE_CSV.write_text(
        "weekday,start,end,stop_after,enabled\n"
        "mon,07:00,23:00,,true\n"
        "tue,07:00,23:00,,true\n"
        "wed,07:00,23:00,,false\n"
        "thu,07:00,23:00,,true\n"
        "fri,07:00,23:00,,true\n"
        "sat,07:00,23:00,,true\n"
        "sun,07:00,23:00,,true\n"
    )
    wed_noon = dt.datetime(2026, 5, 27, 12, 0).astimezone()
    allowed, nxt = schedule.is_in_allowed_window(wed_noon)
    assert not allowed
    assert nxt is not None
    # restore
    schedule.SCHEDULE_INI.write_text(schedule.DEFAULT_INI)


# ---------- stop_after parsing ----------
def test_stop_after_for_today_default_is_D():
    # CSV disabled → stop_after = D always
    assert schedule.stop_after_for_today() == "D"


def test_csv_with_stop_after_b():
    schedule.SCHEDULE_INI.write_text(
        schedule.DEFAULT_INI.replace("use_schedule_csv = false",
                                     "use_schedule_csv = true"))
    schedule.SCHEDULE_CSV.write_text(
        "weekday,start,end,stop_after,enabled\n"
        "mon,00:00,23:59,B,true\n"
        "tue,00:00,23:59,B,true\n"
        "wed,00:00,23:59,B,true\n"
        "thu,00:00,23:59,B,true\n"
        "fri,00:00,23:59,B,true\n"
        "sat,00:00,23:59,B,true\n"
        "sun,00:00,23:59,B,true\n"
    )
    assert schedule.stop_after_for_today() == "B"
    schedule.SCHEDULE_INI.write_text(schedule.DEFAULT_INI)


def test_csv_comments_skipped():
    """Lines starting with # should be ignored by CSV parser."""
    schedule.SCHEDULE_CSV.write_text(
        "# this is a comment\n"
        "# another comment\n"
        "weekday,start,end,stop_after,enabled\n"
        "mon,07:00,23:00,C,true\n"
    )
    windows = schedule.load_csv_windows()
    assert "mon" in windows
    assert windows["mon"]["stop_after"] == "C"
