#!/usr/bin/env bash
# run.sh is deprecated. Everything is now Python.
#
# Use one of these instead:
#     python sw.py <command>            # zero install
#     ./sw.py <command>                 # ./sw.py is executable
#     sw <command>                      # after `pip install -e .`
#     python -m orchestrator <command>  # package mode
#
# This file forwards to sw.py for backward compatibility. Safe to delete.

set -uo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/sw.py" "$@"
