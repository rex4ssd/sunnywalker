"""Failure summary — quick-read markdown when an agent crashes/times-out/fails.

Written immediately by orchestrator when failure is detected, so the user
doesn't need to grep through 4 different files.

File path:  orchestrator/logs/<DATE>/_failure_<agent>_day<N>.md

The latest summary can be viewed via `sw fail`.
"""
from __future__ import annotations
import datetime as dt
from pathlib import Path

from .paths import LOGS, today_log_dir


# Default tails — tunable per call
LOG_TAIL_LINES = 60
BUILD_TAIL_LINES = 80


def _tail(path: Path, n: int) -> str:
    if not path.exists():
        return "(file does not exist)"
    try:
        # Read whole file (these logs are not huge) then take last n lines
        lines = path.read_text(errors="replace").splitlines()
        return "\n".join(lines[-n:]) if lines else "(empty)"
    except OSError as e:
        return f"(could not read: {e})"


# Heuristic hints — common failure patterns
HINTS = [
    ("rate limit",       "Token / API rate limit. Cooldown should already be set."),
    ("rate_limit",       "Token / API rate limit. Cooldown should already be set."),
    ("429",              "Rate limit (HTTP 429). Cooldown should already be set."),
    ("quota",            "Quota exhausted. Wait for refresh or change model."),
    ("credit",           "Account credit issue. Check billing."),
    ("requires --verbose","claude CLI flag mismatch — orchestrator should have --verbose."),
    ("Trust",            "claude OAuth trust prompt — run `claude` once in this folder, press Yes."),
    ("CommandLineTools", "xcode-select pointing at CLT, not Xcode. Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"),
    ("No such module",   "Swift import missing — Day's code added a dependency not in project."),
    ("error: ",          "Compile error in Swift. See build log."),
    ("XCTAssert",        "Test assertion failed — check test log."),
    ("max-turns",        "Hit max-turns limit. Increase in config.yaml or split the task."),
    ("not appended",     "Agent finished without writing a DONE entry. May need clearer prompt or more turns."),
]


def diagnose(blob: str) -> list[str]:
    blob_l = blob.lower()
    hits = []
    for needle, hint in HINTS:
        if needle.lower() in blob_l:
            hits.append(hint)
    # dedup, preserve order
    seen = set()
    out = []
    for h in hits:
        if h not in seen:
            seen.add(h)
            out.append(h)
    return out


def write(
    agent: str,
    day: int,
    role: str,
    model: str,
    reason: str,
    agent_log: Path,
    extra_log_files: list[Path] | None = None,
    date_str: str | None = None,
) -> Path:
    """Produce _failure_<agent>_day<N>.md for the current date.

    Returns the path so caller can print it / notify on it.
    """
    date_str = date_str or dt.date.today().isoformat()
    log_dir = today_log_dir(date_str)
    out = log_dir / f"_failure_{agent.lower()}_day{day}.md"

    # Gather all log content for hint detection
    blobs = []
    if agent_log.exists():
        blobs.append(agent_log.read_text(errors="replace")[-8000:])
    for f in (extra_log_files or []):
        if f.exists():
            blobs.append(f.read_text(errors="replace")[-4000:])
    diagnostics = diagnose("\n".join(blobs))

    lines: list[str] = []
    lines.append(f"# 🔥 FAILURE: [{agent}] Day {day} — {dt.datetime.now().astimezone().isoformat(sep=' ', timespec='seconds')}")
    lines.append("")
    lines.append(f"- **Role**: {role}")
    lines.append(f"- **Model**: {model}")
    lines.append(f"- **Reason**: {reason}")
    lines.append("")

    if diagnostics:
        lines.append("## 🩺  Diagnostic hints (auto-detected)")
        for h in diagnostics:
            lines.append(f"- {h}")
        lines.append("")

    lines.append("## 📄  Agent log (last lines)")
    lines.append(f"Source: `{agent_log}`")
    lines.append("")
    lines.append("```")
    lines.append(_tail(agent_log, LOG_TAIL_LINES))
    lines.append("```")
    lines.append("")

    for f in (extra_log_files or []):
        lines.append(f"## 📄  {f.name} (last lines)")
        lines.append(f"Source: `{f}`")
        lines.append("")
        lines.append("```")
        lines.append(_tail(f, BUILD_TAIL_LINES))
        lines.append("```")
        lines.append("")

    lines.append("## 🔧  Next steps")
    lines.append("1. Read the logs above to understand the root cause.")
    lines.append("2. Apply a fix (edit code, change config, etc.).")
    lines.append(f"3. `sw resolve` — clear the FAILED entry in ring.md.")
    lines.append(f"4. `sw next` — retry the same agent.")
    lines.append(f"   Or force a specific agent: `sw {role}`.")
    lines.append("")

    out.write_text("\n".join(lines), encoding="utf-8")
    return out


def latest_summary() -> Path | None:
    """Find the most recent _failure_*.md across all log dirs."""
    if not LOGS.exists():
        return None
    candidates = sorted(LOGS.rglob("_failure_*.md"),
                       key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None
