#!/usr/bin/env python3
"""
claude_loop orchestrator — thin driver around the lib/ modules.

Pipeline state lives in:
    - orchestrator/current/ring.md          (baton)
    - orchestrator/current/heartbeat.json   (crash detection)
    - MAIN_ENTRY.md                          (resume manifest at project root)
    - orchestrator/reports/daily/*.md        (2-min summaries)
    - orchestrator/reports/weekly/*.md       (rollups)
    - orchestrator/progress/progress.md      (live TODO)
    - orchestrator/logs/<date>/              (verbose, archived after day completes)
    - orchestrator/archive/<YYYY-MM>/<date>/ (cold storage)

Usage:
    python orchestrator.py next       # auto-detect who's next, run them
    python orchestrator.py today      # keep running until day's D completes
    python orchestrator.py status     # show MAIN_ENTRY
    python orchestrator.py ring       # cat ring.md
    python orchestrator.py resume     # explicit crash recovery
    python orchestrator.py recover    # alias for resume
    python orchestrator.py archive    # archive completed day's verbose logs
    python orchestrator.py weekly     # generate this week's report
    python orchestrator.py resolve    # mark a FAILED entry as human-resolved
    python orchestrator.py daily      # regenerate today's daily report
    python orchestrator.py refresh    # regenerate MAIN_ENTRY.md + progress.md
    python orchestrator.py coder|validator|reporter|reviewer   # force-run
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import yaml

# Local imports
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import archive, heartbeat, main_entry, notify, paths, reports, ring, schedule  # noqa


# ---------- token-limit detection ----------
TOKEN_LIMIT_PATTERNS = [
    "rate limit", "rate_limit", "rate-limit",
    "credit", "quota", "usage limit",
    "insufficient_quota", "billing",
    "429",
]


def looks_like_token_limit(log_file: Path) -> bool:
    try:
        tail = log_file.read_text(errors="ignore")[-4000:].lower()
    except OSError:
        return False
    return any(p in tail for p in TOKEN_LIMIT_PATTERNS)


# ---------- agent ----------
@dataclass
class Agent:
    name: str           # A / B / C / D
    role: str
    model: str
    prompt_file: Path
    timeout_s: int
    allowed_tools: list[str]
    project_name: str
    project_description: str
    dry_run: bool = False

    def run(self, day: int) -> bool:
        paths.ensure_dirs()
        log_dir = paths.today_log_dir()
        log_file = log_dir / f"{self.name.lower()}_{self.role}.log"

        # Heartbeat first — so a crash mid-run leaves evidence
        heartbeat.write(self.name, day, log_file)

        # Stamp IN_PROGRESS on ring (orchestrator-injected; agent will replace
        # with DONE entry on completion)
        ring.append_in_progress(self.name, day, self.model)

        # Build brief (only paths; the prompt template handles instructions)
        brief = self._build_brief(day, log_dir, log_file)
        full_prompt = self.prompt_file.read_text(encoding="utf-8").replace(
            "{{BRIEF}}", brief)

        cmd = [
            "claude",
            "-p", full_prompt,
            "--output-format", "stream-json",
            "--verbose",            # required by claude CLI when -p uses stream-json
            "--model", self.model,
            "--max-turns", "60",
        ]
        if self.allowed_tools:
            cmd += ["--allowedTools", ",".join(self.allowed_tools)]

        print(f"\n[{self.name}] {self.role}  Day {day}  model={self.model}")
        print(f"      log:       {log_file}")
        print(f"      ring:      {paths.RING}")
        print(f"      heartbeat: {paths.HEARTBEAT}")

        if self.dry_run:
            print(f"\n[--dry-run] would invoke:")
            print(f"  {' '.join(cmd[:4])} ... (prompt {len(full_prompt)} chars, "
                  f"allowed_tools={','.join(self.allowed_tools)})")
            print(f"\n[--dry-run] prompt preview (first 500 chars):")
            print(full_prompt[:500])
            print("...\n")
            heartbeat.clear()
            return True

        with log_file.open("w", encoding="utf-8") as logf:
            logf.write(f"# Agent {self.name} ({self.role})  Day {day}\n")
            logf.write(f"# Started: {dt.datetime.now().isoformat(timespec='seconds')}\n")
            logf.write(f"# PID: {os.getpid()}\n")
            logf.write("=" * 60 + "\n\n")
            logf.flush()

            try:
                proc = subprocess.Popen(
                    cmd, cwd=paths.ROOT,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, bufsize=1,
                )
                t0 = time.time()
                for line in proc.stdout:
                    logf.write(line)
                    logf.flush()
                    if time.time() - t0 > self.timeout_s:
                        proc.kill()
                        raise TimeoutError(f"exceeded {self.timeout_s}s")
                rc = proc.wait()
            except TimeoutError as e:
                logf.write(f"\n!!! TIMEOUT: {e}\n")
                ring.append_failed(self.name, day, f"Timeout: {e}", log_file)
                heartbeat.clear()
                return False
            except Exception as e:
                logf.write(f"\n!!! EXCEPTION: {e}\n")
                ring.append_failed(self.name, day, f"Exception: {e}", log_file)
                heartbeat.clear()
                return False

        # Subprocess returned. Diagnose outcome.
        if rc != 0:
            if looks_like_token_limit(log_file):
                until = schedule.mark_token_paused("token_limit")
                ring.append_token_paused(self.name, day, log_file,
                                        retry_after=until.isoformat(sep=" ", timespec="seconds"))
                print(f"[{self.name}] PAUSED — token limit hit.")
                print(f"   Cooldown until: {until} ({schedule.cooldown_hours()}h)")
                print(f"   Next `sw next` will exit silently until then.")
                notify.notify_token_limit(
                    until.isoformat(sep=" ", timespec="seconds"),
                    schedule.cooldown_hours())
                heartbeat.clear()
                return False
            ring.append_failed(self.name, day, f"Subprocess rc={rc}", log_file)
            notify.notify_failed(day, self.name, str(log_file))
            heartbeat.clear()
            return False

        # Sanity: did the agent actually append a DONE entry?
        last = ring.last()
        if last and last.agent == self.name and last.status == "DONE":
            print(f"[{self.name}] DONE  ({int(time.time() - t0)}s)")
            heartbeat.clear()
            return True

        ring.append_failed(self.name, day,
                           f"Subprocess rc={rc} but no DONE entry appended by agent",
                           log_file)
        heartbeat.clear()
        return False

    def _build_brief(self, day: int, log_dir: Path, log_file: Path) -> str:
        spec = paths.ROOT / self._spec_relative_path()
        return (
            f"## Project\n{self.project_name}\n\n"
            f"## Project description\n{self.project_description}\n\n"
            f"## Working directory\n{paths.ROOT}\n\n"
            f"## Day number\n{day}\n\n"
            f"## Ring file (read first, append your entry at the end)\n{paths.RING}\n\n"
            f"## Spec\n{spec}\n\n"
            f"## Verbose log file (your stdout is being captured here automatically)\n{log_file}\n\n"
            f"## Today's log directory\n{log_dir}\n\n"
            f"## Heartbeat file (DO NOT EDIT — orchestrator manages it)\n{paths.HEARTBEAT}\n"
        )

    def _spec_relative_path(self) -> str:
        return _GLOBAL_CFG.get("spec_path", "docs/spec.md")


# Global config holder so Agent._build_brief can access spec_path without
# threading it through everything
_GLOBAL_CFG: dict = {}


# ---------- factory ----------
def load_config() -> dict:
    if not paths.CONFIG.exists():
        raise SystemExit(f"Missing config: {paths.CONFIG}")
    with paths.CONFIG.open() as f:
        return yaml.safe_load(f)


def build_agents(cfg: dict, dry_run: bool = False) -> dict[str, Agent]:
    global _GLOBAL_CFG
    _GLOBAL_CFG = cfg
    a = cfg["agents"]
    project = cfg.get("project", {})
    pname = project.get("name", paths.ROOT.name)
    pdesc = project.get("description", "")
    return {
        "coder":     Agent("A", "coder",     a["coder"]["model"],
                           paths.PROMPTS / "01_coder.md",     a["coder"]["timeout_s"],
                           ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
                           pname, pdesc, dry_run),
        "validator": Agent("B", "validator", a["validator"]["model"],
                           paths.PROMPTS / "02_validator.md", a["validator"]["timeout_s"],
                           ["Read", "Write", "Bash"], pname, pdesc, dry_run),
        "reporter":  Agent("C", "reporter",  a["reporter"]["model"],
                           paths.PROMPTS / "03_reporter.md",  a["reporter"]["timeout_s"],
                           ["Read", "Write", "Bash"], pname, pdesc, dry_run),
        "reviewer":  Agent("D", "reviewer",  a["reviewer"]["model"],
                           paths.PROMPTS / "04_reviewer.md",  a["reviewer"]["timeout_s"],
                           ["Read", "Write", "Glob", "Grep"], pname, pdesc, dry_run),
    }


# ---------- post-run hooks ----------
def post_agent(cfg: dict, just_ran: str) -> None:
    """Update MAIN_ENTRY + progress.md after each agent completes."""
    project = cfg.get("project", {})
    main_entry.write(project.get("name", paths.ROOT.name),
                     project.get("description", ""))
    reports.write_progress(cfg.get("milestones", []))

    last = ring.last()

    # Check if the agent that just ran is the day's configured stop_after.
    # If yes, gate the rest of today behind explicit approval.
    if last and last.status == "DONE" and last.agent in {"A", "B", "C"}:
        stop_after = schedule.stop_after_for_today()
        if last.agent == stop_after and not schedule.is_awaiting_approval()[0]:
            schedule.mark_awaiting_approval(last.agent,
                f"schedule.csv stop_after={stop_after}")
            print(f"\n⏸  Day {last.day} paused after [{last.agent}] per schedule.")
            print(f"   Review the ring, then run `sw approve` to continue.")
            notify.notify_approval_needed(last.agent, last.day)

    # Human attention flag from D
    if last and last.human_attention:
        notify.notify_human_attention(last.day, last.human_attention)

    # If D just finished and stamped End of Day -> generate daily + archive
    if last and last.agent == "D" and last.end_of_day is not None:
        date_str = dt.date.today().isoformat()
        reports.write_daily(date_str)
        # Notify with verdict if we can find one
        verdict = "unknown"
        import re
        m = re.search(r"### Verdict:\s*(\S+)", last.raw)
        if m:
            verdict = m.group(1)
        notify.notify_day_complete(last.end_of_day, verdict)

        if cfg.get("auto_archive_on_day_complete", True):
            archive.archive_day(date_str, last.end_of_day)
            print(f"📦 Archived Day {last.end_of_day} to "
                  f"orchestrator/archive/{date_str[:7]}/{date_str}/")
        if dt.date.today().weekday() == 6:
            reports.write_weekly()
        main_entry.write(project.get("name", paths.ROOT.name),
                         project.get("description", ""))


# ---------- schedule gate ----------
def _check_schedule_gate() -> bool:
    """Returns True if pipeline is allowed to run now. Otherwise prints and returns False."""
    ok, reason, until = schedule.can_run_now()
    if ok:
        return True
    print(f"⏸  Cannot run now: {reason}")
    if until:
        now = dt.datetime.now().astimezone()
        delta = until - now
        mins = int(delta.total_seconds() / 60)
        print(f"   Next allowed: {until.isoformat(sep=' ', timespec='seconds')} "
              f"(~{mins} min)")
    print(f"   Run `./run.sh schedule` for details.")
    print(f"   Run `./run.sh clear-cooldown` to force-clear (use sparingly).")
    return False


# ---------- commands ----------
def cmd_next(agents: dict[str, Agent], cfg: dict) -> None:
    if not _check_schedule_gate():
        sys.exit(0)  # exit 0 — cron-friendly
    try:
        role, day = ring.next_agent()
    except RuntimeError as e:
        print(f"!! {e}")
        sys.exit(1)
    print(f"Next up: [{ring.ROLE_TO_LETTER[role]}] {role}  Day {day}")
    ok = agents[role].run(day)
    post_agent(cfg, role)
    if not ok:
        sys.exit(1)


def cmd_today(agents: dict[str, Agent], cfg: dict) -> None:
    if not _check_schedule_gate():
        sys.exit(0)
    while True:
        # Re-check gate each iteration: token limit may trigger mid-day
        if not _check_schedule_gate():
            sys.exit(0)
        last = ring.last()
        if last and last.agent == "D" and last.end_of_day is not None \
                and last.end_of_day == ring.current_day() - 1:
            print(f"Day {last.end_of_day} already complete.")
            return
        try:
            role, day = ring.next_agent()
        except RuntimeError as e:
            print(f"!! {e}")
            sys.exit(1)
        ok = agents[role].run(day)
        post_agent(cfg, role)
        if not ok and cfg.get("stop_on_failure", True):
            print("!! Stopping pipeline.")
            sys.exit(1)
        last = ring.last()
        if last and last.agent == "D" and last.status == "DONE" \
                and last.end_of_day is not None:
            return


def cmd_force(agents: dict[str, Agent], cfg: dict, role: str) -> None:
    # Force commands bypass the schedule gate intentionally — used for debug
    # after manual intervention. Show a warning if currently in cooldown.
    in_cd, until, reason = schedule.is_in_cooldown()
    if in_cd:
        print(f"⚠️  Force-running while in cooldown ({reason}) until {until}")
        print(f"   Token-limit hit again would just renew the cooldown.")
    last = ring.last()
    day = ring.current_day()
    print(f"Force-running [{ring.ROLE_TO_LETTER[role]}] {role}  Day {day}")
    agents[role].run(day)
    post_agent(cfg, role)


def cmd_schedule(_cfg: dict) -> None:
    schedule.ensure_files()
    print(f"schedule.ini: {schedule.SCHEDULE_INI}")
    print(f"schedule.csv: {schedule.SCHEDULE_CSV}")
    print(f"paused_until: {schedule.PAUSED_UNTIL}")
    print(f"approval:     {schedule.APPROVAL}")
    print()
    print(schedule.status_summary())


def cmd_clear_cooldown(_cfg: dict) -> None:
    schedule.clear_cooldown()
    print("Cooldown cleared.")


def cmd_approve(_cfg: dict) -> None:
    gated, payload = schedule.is_awaiting_approval()
    if not gated:
        print("No approval gate active. Nothing to clear.")
        return
    schedule.clear_approval()
    print(f"Approved. Pipeline can proceed past [{payload.get('stopped_after')}].")
    print("Run `sw next` to continue today's work.")


def cmd_status(cfg: dict) -> None:
    if paths.MAIN_ENTRY.exists():
        print(paths.MAIN_ENTRY.read_text())
    else:
        print("(MAIN_ENTRY.md does not exist yet — run `./run.sh refresh`)")


def cmd_ring(_cfg: dict) -> None:
    print(ring.read_text())


def cmd_resume(agents: dict[str, Agent], cfg: dict) -> None:
    """Crash recovery. Detect stale heartbeat + in-progress ring entry."""
    stale, hb = heartbeat.is_stale()
    last = ring.last()

    print("== Resume diagnostic ==")
    if hb:
        alive = heartbeat.is_process_alive()
        print(f"Heartbeat: agent=[{hb.get('agent')}] day={hb.get('day')} "
              f"started={hb.get('started_at')} alive={alive} stale={stale}")
    else:
        print("Heartbeat: none")
    if last:
        print(f"Last ring entry: [{last.agent}] Day {last.day} {last.status}")

    if last and last.status == "IN_PROGRESS":
        if hb and heartbeat.is_process_alive():
            print("!! Process is still alive — refusing to resume. Wait or kill manually.")
            sys.exit(1)
        # Mark the in-progress entry as failed, then user can decide
        # whether to retry the same agent or escalate
        log_file = (Path(hb["log_path"]) if hb and "log_path" in hb
                    else paths.today_log_dir() / "unknown.log")
        ring.append_failed(last.agent, last.day,
                          "Process died (heartbeat stale, PID dead). "
                          "Resume detected mid-run crash.",
                          log_file)
        print("Marked previous IN_PROGRESS as FAILED.")
        print("Next step: read the log, then run `./run.sh resolve` to clear,")
        print("           or fix the issue and run `./run.sh next` to retry from the same agent.")
        post_agent(cfg, last.role)
        return

    print("No crash detected. Running next normally...")
    cmd_next(agents, cfg)


def cmd_archive(cfg: dict) -> None:
    last = ring.last()
    if not last or last.end_of_day is None:
        print("!! No completed day to archive. Last entry must end with `→ End of Day N`.")
        sys.exit(1)
    date_str = dt.date.today().isoformat()
    target = archive.archive_day(date_str, last.end_of_day)
    print(f"Archived Day {last.end_of_day} to {target}")


def cmd_weekly(_cfg: dict) -> None:
    path = reports.write_weekly()
    print(f"Wrote weekly report: {path}")


def cmd_daily(_cfg: dict) -> None:
    path = reports.write_daily()
    print(f"Wrote daily report: {path}")


def cmd_resolve(cfg: dict) -> None:
    try:
        ring.mark_resolved()
        print("Marked previous FAILED entry as human-resolved.")
        post_agent(cfg, "resolve")
    except RuntimeError as e:
        print(f"!! {e}")
        sys.exit(1)


def cmd_refresh(cfg: dict) -> None:
    paths.ensure_dirs()
    project = cfg.get("project", {})
    main_entry.write(project.get("name", paths.ROOT.name),
                     project.get("description", ""))
    reports.write_progress(cfg.get("milestones", []))
    print(f"Refreshed: {paths.MAIN_ENTRY}")
    print(f"           {paths.PROGRESS}")


# ---------- entry ----------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=[
        "next", "today", "status", "ring", "resume", "recover",
        "archive", "weekly", "daily", "resolve", "refresh",
        "schedule", "clear-cooldown", "approve", "clear-approval",
        "coder", "validator", "reporter", "reviewer",
    ])
    parser.add_argument("--dry-run", action="store_true",
                        help="Print prompts and intended actions without invoking claude.")
    parser.add_argument("--model",
                        help="Override the model for ALL agents this run "
                             "(e.g. --model claude-sonnet-4-6). Useful for saving "
                             "Opus quota — run all 4 with Sonnet/Haiku.")
    args = parser.parse_args()

    cfg = load_config()
    paths.ensure_dirs()

    # Apply --model override across all agents
    if args.model:
        for role in ("coder", "validator", "reporter", "reviewer"):
            cfg["agents"][role]["model"] = args.model
        print(f"[override] All agents using model: {args.model}")

    agents = build_agents(cfg, dry_run=args.dry_run)

    dispatch = {
        "next":             lambda: cmd_next(agents, cfg),
        "today":            lambda: cmd_today(agents, cfg),
        "status":           lambda: cmd_status(cfg),
        "ring":             lambda: cmd_ring(cfg),
        "resume":           lambda: cmd_resume(agents, cfg),
        "recover":          lambda: cmd_resume(agents, cfg),
        "archive":          lambda: cmd_archive(cfg),
        "weekly":           lambda: cmd_weekly(cfg),
        "daily":            lambda: cmd_daily(cfg),
        "resolve":          lambda: cmd_resolve(cfg),
        "refresh":          lambda: cmd_refresh(cfg),
        "schedule":         lambda: cmd_schedule(cfg),
        "clear-cooldown":   lambda: cmd_clear_cooldown(cfg),
        "approve":          lambda: cmd_approve(cfg),
        "clear-approval":   lambda: cmd_approve(cfg),  # alias
    }
    if args.command in dispatch:
        dispatch[args.command]()
    else:  # force-run a specific agent
        cmd_force(agents, cfg, args.command)


if __name__ == "__main__":
    main()
