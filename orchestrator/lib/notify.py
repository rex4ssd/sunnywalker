"""macOS desktop notification helper.

Fire-and-forget notifier using osascript. Falls back to print on non-mac.
Designed to be silent on failure — never crash the pipeline because of
a notification.

Use cases:
    notify_approval_needed(stopped_after, day)
    notify_token_limit(retry_at)
    notify_human_attention(reason)
    notify_day_complete(day, verdict)
"""
from __future__ import annotations
import platform
import shlex
import subprocess


def is_macos() -> bool:
    return platform.system() == "Darwin"


def notify(title: str, body: str, sound: str | None = "Glass") -> bool:
    """Show a desktop notification. Returns True if posted, False otherwise."""
    if not is_macos():
        print(f"[notify] {title} — {body}")
        return False
    # Escape backslashes and double-quotes for AppleScript string literals.
    t = title.replace("\\", "\\\\").replace('"', '\\"')
    b = body.replace("\\", "\\\\").replace('"', '\\"')
    sound_clause = f' sound name "{sound}"' if sound else ""
    script = f'display notification "{b}" with title "{t}"{sound_clause}'
    try:
        subprocess.run(["osascript", "-e", script],
                       check=False, timeout=5,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (subprocess.SubprocessError, FileNotFoundError):
        return False


# ---------- semantic helpers ----------
def notify_approval_needed(stopped_after: str, day: int) -> None:
    notify(
        title=f"SunnyWalker — Day {day} paused",
        body=f"Stopped after [{stopped_after}]. Review the ring then run `sw approve`.",
        sound="Glass",
    )


def notify_token_limit(retry_at: str, hours: float) -> None:
    notify(
        title="SunnyWalker — Token limit hit",
        body=f"Pipeline paused for {hours}h. Next allowed: {retry_at}",
        sound="Basso",
    )


def notify_human_attention(day: int, reason: str) -> None:
    notify(
        title=f"🚨 SunnyWalker — Day {day} needs you",
        body=reason,
        sound="Sosumi",
    )


def notify_day_complete(day: int, verdict: str) -> None:
    emoji = {"on_track": "✅", "at_risk": "⚠️", "off_track": "❌"}.get(verdict, "❔")
    notify(
        title=f"SunnyWalker — Day {day} complete {emoji}",
        body=f"Verdict: {verdict}. See today's report.",
        sound="Hero",
    )


def notify_failed(day: int, agent: str, log_path: str) -> None:
    notify(
        title=f"SunnyWalker — Day {day} agent [{agent}] FAILED",
        body=f"Full log: {log_path}",
        sound="Basso",
    )
