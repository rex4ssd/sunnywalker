#!/usr/bin/env python3
"""sw — single Python entry point for the claude_loop pipeline.

Three ways to run:

    1. Direct, no install:
           python sw.py next
           ./sw.py next         # if executable

    2. After `pip install -e .`:
           sw next

    3. As module:
           python -m orchestrator next

This file auto-bootstraps a venv on first run (if none exists), installs
PyYAML, then delegates to orchestrator.orchestrator.main().

It also verifies the `claude` CLI is reachable (OAuth login or
ANTHROPIC_API_KEY) before invoking any agent.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VENV = HERE / ".venv"
VENV_PY = VENV / "bin" / "python"
REQ = HERE / "orchestrator" / "requirements.txt"

# Subset of commands that do not call `claude` CLI — they only read/write
# local files. We skip the claude-CLI check for these.
LOCAL_ONLY_CMDS = {
    "status", "ring", "schedule", "clear-cooldown",
    "daily", "weekly", "archive", "refresh", "resolve",
}


def in_venv() -> bool:
    return sys.prefix != sys.base_prefix


def bootstrap_venv_and_relaunch() -> None:
    """If no venv yet, create it, install deps, re-exec self under venv python."""
    if not VENV_PY.exists():
        print(f"[bootstrap] creating venv at {VENV}")
        subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
        print("[bootstrap] installing requirements")
        subprocess.run([str(VENV / "bin" / "pip"), "install", "-q", "-U", "pip"],
                       check=True)
        subprocess.run([str(VENV / "bin" / "pip"), "install", "-q", "-r", str(REQ)],
                       check=True)
    # Re-exec under venv python so deps are visible
    os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve())] + sys.argv[1:])


def check_claude_cli() -> None:
    if shutil.which("claude") is None:
        print("!! 'claude' CLI not found.")
        print("   Install:  npm i -g @anthropic-ai/claude-code")
        sys.exit(1)
    if not os.environ.get("ANTHROPIC_API_KEY"):
        # claude CLI may still work via OAuth login — silently allow
        pass


def main() -> None:
    # Step 1: if invoked with system python and venv exists, re-exec under venv
    if not in_venv() and VENV_PY.exists() and Path(sys.executable) != VENV_PY:
        os.execv(str(VENV_PY), [str(VENV_PY), str(Path(__file__).resolve())] + sys.argv[1:])

    # Step 2: if no venv at all and PyYAML missing, bootstrap
    try:
        import yaml  # noqa: F401
    except ImportError:
        bootstrap_venv_and_relaunch()

    # Step 3: if command will spawn claude, check the CLI is reachable
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd not in LOCAL_ONLY_CMDS:
        check_claude_cli()

    # Step 4: delegate
    sys.path.insert(0, str(HERE))
    from orchestrator.orchestrator import main as orch_main
    orch_main()


if __name__ == "__main__":
    main()
