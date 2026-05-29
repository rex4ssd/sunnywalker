"""Ring file — the append-only baton between agents.

States we recognize:
    DONE                — agent finished, handed off
    IN_PROGRESS         — agent is running (orchestrator-injected stub)
    PAUSED_TOKEN_LIMIT  — agent ran out of credits mid-task (recoverable)
    FAILED              — unrecoverable; needs human

Last-entry parser tells us who runs next, or that day is complete.
"""
from __future__ import annotations
import datetime as dt
import re
from dataclasses import dataclass
from pathlib import Path

from .paths import RING

RING_HEADER = """# Ring — agent baton

> Append-only handoff file between agents (A -> B -> C -> D -> A ...).
> Each agent: read entire ring, find last entry, do work, append exactly ONE entry,
> stamp `→ Hand off to <X>` or `→ End of Day N` at the end.
>
> Never edit past entries. To correct, append a new entry.

"""

# Accept any letter A-H so we can also match human-resolved (H) entries.
# Timestamp can be ISO with T separator OR with space separator — match anything
# non-greedy up to end of line.
ENTRY_RE   = re.compile(r"^## \[([A-H])\] Day (\d+) — (.+?)\s*$", re.MULTILINE)
STATUS_RE  = re.compile(r"^Status:\s*([A-Z_]+)\s*$", re.MULTILINE)
HANDOFF_RE = re.compile(r"^→ Hand off to ([ABCD])\s*$", re.MULTILINE)
EOD_RE     = re.compile(r"^→ End of Day (\d+)\s*$", re.MULTILINE)
ATTN_RE    = re.compile(r"^🚨 HUMAN ATTENTION:\s*(.+)$", re.MULTILINE)

LETTER_TO_ROLE = {"A": "coder", "B": "validator", "C": "reporter", "D": "reviewer",
                  "H": "human"}
ROLE_TO_LETTER = {v: k for k, v in LETTER_TO_ROLE.items() if k != "H"}


@dataclass
class Entry:
    agent: str           # A / B / C / D
    day: int
    timestamp: str
    status: str          # DONE / IN_PROGRESS / FAILED / PAUSED_TOKEN_LIMIT
    handoff_to: str | None
    end_of_day: int | None
    human_attention: str | None
    raw: str

    @property
    def role(self) -> str:
        return LETTER_TO_ROLE[self.agent]


def _ensure_ring() -> None:
    RING.parent.mkdir(parents=True, exist_ok=True)
    if not RING.exists() or RING.stat().st_size == 0:
        RING.write_text(RING_HEADER, encoding="utf-8")


def read_text() -> str:
    _ensure_ring()
    return RING.read_text(encoding="utf-8")


def entries() -> list[Entry]:
    text = read_text()
    positions = list(ENTRY_RE.finditer(text))
    out: list[Entry] = []
    for i, m in enumerate(positions):
        end = positions[i + 1].start() if i + 1 < len(positions) else len(text)
        block = text[m.start():end]
        status_m = STATUS_RE.search(block)
        handoff_m = HANDOFF_RE.search(block)
        eod_m = EOD_RE.search(block)
        attn_m = ATTN_RE.search(block)
        out.append(Entry(
            agent=m.group(1),
            day=int(m.group(2)),
            timestamp=m.group(3),
            status=(status_m.group(1) if status_m else "UNKNOWN"),
            handoff_to=(handoff_m.group(1) if handoff_m else None),
            end_of_day=(int(eod_m.group(1)) if eod_m else None),
            human_attention=(attn_m.group(1).strip() if attn_m else None),
            raw=block,
        ))
    return out


def last() -> Entry | None:
    e = entries()
    return e[-1] if e else None


def next_agent() -> tuple[str, int]:
    """Return (role_name, day_number) for who should run next."""
    e = last()
    if e is None:
        return ("coder", 1)
    if e.status in ("IN_PROGRESS", "PAUSED_TOKEN_LIMIT"):
        return (e.role, e.day)
    if e.status == "FAILED":
        raise RuntimeError(
            f"Last entry [{e.agent}] Day {e.day} is FAILED. "
            "Run a specific agent manually after fixing, "
            "or run `./run.sh resolve` to mark resolved."
        )
    if e.end_of_day is not None:
        return ("coder", e.end_of_day + 1)
    if e.handoff_to:
        return (LETTER_TO_ROLE[e.handoff_to], e.day)
    raise RuntimeError(f"Cannot determine next from entry: {e.raw[:200]}")


def _now_ts() -> str:
    """Timestamp with space separator (more readable in markdown)."""
    return dt.datetime.now().astimezone().isoformat(sep=" ", timespec="seconds")


def append_in_progress(agent_letter: str, day: int, model: str) -> str:
    _ensure_ring()
    ts = _now_ts()
    stub = (
        f"\n## [{agent_letter}] Day {day} — {ts}\n"
        f"Status: IN_PROGRESS\n"
        f"Model:  {model}\n\n"
        f"_(orchestrator stub — agent is running; replaced by agent's DONE entry on completion)_\n\n"
    )
    with RING.open("a", encoding="utf-8") as f:
        f.write(stub)
    return ts


def append_failed(agent_letter: str, day: int, reason: str, log_path: Path) -> None:
    _ensure_ring()
    ts = _now_ts()
    block = (
        f"\n## [{agent_letter}] Day {day} — {ts} (orchestrator-injected)\n"
        f"Status: FAILED\n"
        f"Model:  (orchestrator)\n\n"
        f"### Reason\n{reason}\n\n"
        f"### Full log\n`{log_path}`\n\n"
        f"### For next\n"
        f"**Human intervention required.** Read the full log above. "
        f"After fixing, run `./run.sh resolve` then `./run.sh next`.\n"
    )
    with RING.open("a", encoding="utf-8") as f:
        f.write(block)


def append_token_paused(agent_letter: str, day: int, log_path: Path,
                        retry_after: str = "later") -> None:
    _ensure_ring()
    ts = _now_ts()
    block = (
        f"\n## [{agent_letter}] Day {day} — {ts} (orchestrator-injected)\n"
        f"Status: PAUSED_TOKEN_LIMIT\n"
        f"Model:  (orchestrator)\n\n"
        f"### Reason\nToken / rate limit hit. Subprocess returned credit-exhausted error.\n\n"
        f"### Last log\n`{log_path}`\n\n"
        f"### For next\n"
        f"Auto-retryable. Run `./run.sh next` again when usage refreshes ({retry_after}).\n"
    )
    with RING.open("a", encoding="utf-8") as f:
        f.write(block)


def mark_resolved() -> None:
    """Append a note that the human has resolved the previous FAILED entry."""
    _ensure_ring()
    ts = _now_ts()
    e = last()
    if e is None or e.status != "FAILED":
        raise RuntimeError("No FAILED entry to resolve.")
    block = (
        f"\n## [H] Day {e.day} — {ts}\n"
        f"Status: DONE\n"
        f"Model:  (human)\n\n"
        f"### What I did\n- Manually resolved the preceding FAILED entry.\n\n"
        f"### For next ({e.agent} — {LETTER_TO_ROLE[e.agent]})\n"
        f"Resume from where you crashed. Re-read your brief and continue.\n\n"
        f"→ Hand off to {e.agent}\n"
    )
    with RING.open("a", encoding="utf-8") as f:
        f.write(block)


def entries_for_day(day: int) -> list[Entry]:
    return [e for e in entries() if e.day == day]


def current_day() -> int:
    e = last()
    if e is None:
        return 1
    if e.end_of_day is not None:
        return e.end_of_day + 1
    return e.day


def rotate_after_day(day: int, archive_path: Path) -> None:
    """Move day's entries out of ring into archive; keep just the previous-day
    closing entry (so A can read D's brief next day)."""
    text = read_text()
    positions = list(ENTRY_RE.finditer(text))
    if not positions:
        return

    # Snapshot ring as-is
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    archive_path.write_text(text, encoding="utf-8")

    # Find the LAST entry of the day (should be D's End of Day)
    day_entries = [(i, m) for i, m in enumerate(positions)
                   if int(m.group(2)) == day]
    if not day_entries:
        return

    # Find the start of the first day-N entry
    first_idx, first_m = day_entries[0]
    last_idx, last_m = day_entries[-1]

    # Keep everything before day N entries  +  just the last (D's eod) entry
    pre = text[:first_m.start()]
    last_end = (positions[last_idx + 1].start()
                if last_idx + 1 < len(positions) else len(text))
    last_block = text[last_m.start():last_end]

    new_text = pre + last_block
    RING.write_text(new_text, encoding="utf-8")
