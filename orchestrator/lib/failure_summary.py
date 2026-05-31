"""Failure summary — quick-read markdown when an agent crashes/times-out/fails.

Written immediately by orchestrator when failure is detected, so the user
doesn't need to grep through 4 different files.

File path:  orchestrator/logs/<DATE>/_failure_<agent>_day<N>.md

The latest summary can be viewed via `sw fail`.
"""
from __future__ import annotations
import datetime as dt
import json
from pathlib import Path

from .paths import LOGS, today_log_dir


# Default tails — tunable per call
LOG_TAIL_LINES = 60
BUILD_TAIL_LINES = 80


def _tail(path: Path, n: int) -> str:
    if not path.exists():
        return "(file does not exist)"
    try:
        lines = path.read_text(errors="replace").splitlines()
        return "\n".join(lines[-n:]) if lines else "(empty)"
    except OSError as e:
        return f"(could not read: {e})"


def _parse_jsonl_log(path: Path, max_chars: int = 3000) -> str:
    """Extract human-readable content from an agent log (JSONL or plain text).
    Processes line-by-line: JSON lines are parsed; plain text lines kept as-is."""
    if not path.exists():
        return "(file does not exist)"
    try:
        raw = path.read_text(errors="replace")
    except OSError as e:
        return f"(could not read: {e})"

    lines = raw.splitlines()
    has_json = any(l.strip().startswith("{") for l in lines)
    if not has_json:
        # Pure plain text log — just tail it
        return "\n".join(lines[-LOG_TAIL_LINES:]) if lines else "(empty)"

    readable: list[str] = []
    for raw_line in lines:
        stripped = raw_line.strip()
        if not stripped:
            continue

        if not stripped.startswith("{"):
            # Plain-text header or annotation — keep it
            readable.append(stripped)
            continue

        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            readable.append(stripped)
            continue

        t = obj.get("type", "")

        # Agent text responses (skip thinking blocks — too verbose)
        if t == "assistant":
            for block in obj.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    txt = block.get("text", "").strip()
                    if txt:
                        readable.append(f"[agent] {txt}")

        # Tool results (bash output, file reads, etc.)
        elif t == "user":
            for block in obj.get("message", {}).get("content", []):
                if block.get("type") != "tool_result":
                    continue
                is_err = block.get("is_error", False)
                tag = "[tool-error]" if is_err else "[tool-result]"
                content = block.get("content", "")
                if isinstance(content, str) and content.strip():
                    readable.append(f"{tag}\n{content[:1200]}")
                elif isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            txt = item.get("text", "")[:1200]
                            if txt.strip():
                                readable.append(f"{tag}\n{txt}")

        # Task failed notifications
        elif t == "system" and obj.get("subtype") == "task_notification":
            if obj.get("status") == "failed":
                readable.append(f"[task-FAILED] {obj.get('summary', '')}")

    result = "\n\n".join(readable)
    if len(result) > max_chars:
        result = "... (earlier output trimmed) ...\n\n" + result[-max_chars:]
    return result or "(no readable content extracted)"


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
    ("error: build input", "Swift compile error — check build log."),
    ("Swift compiler error", "Swift compile error — check build log."),
    ("cannot find type", "Swift compile error: type not found — check build log."),
    ("cannot find '",    "Swift compile error: symbol not found — check build log."),
    ("build input file cannot be found", "Swift file missing from project — check pbxproj."),
    ("Unable to find a device", "⚠️  Simulator not found — check DESTINATION in validate.sh."),
    ("XCTAssert",        "Test assertion failed — check test log."),
    ("max-turns",        "Hit max-turns limit. Increase in config.yaml or split the task."),
    ("not appended",     "Agent finished without writing a DONE entry. May need clearer prompt or more turns."),
    ("haven't granted",  "⚠️  Permission denied — agent couldn't write a file (ring.md?). Check Claude's tool permissions / trust settings."),
    ("permission",       "⚠️  Permission issue — agent was blocked from writing a required file."),
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

    lines.append("## 📄  Agent log (readable summary)")
    lines.append(f"Source: `{agent_log}`")
    lines.append("")
    lines.append("```")
    lines.append(_parse_jsonl_log(agent_log))
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
    lines.append(f"3. `python sw.py resolve` — clear the FAILED entry in ring.md.")
    lines.append(f"4. `python sw.py next` — retry the same agent.")
    lines.append(f"   Or force a specific agent: `python sw.py {role}`.")
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
