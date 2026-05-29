# Reusing claude_loop in a new project

This `orchestrator/` folder is a self-contained framework. To use it in a new
project (e.g. a Mac Tauri app):

## 1. Copy the folder

```bash
cp -r SunnyWalker/orchestrator/  my_new_project/orchestrator/
cp    SunnyWalker/run.sh         my_new_project/run.sh
cp    SunnyWalker/scripts/dev.sh my_new_project/scripts/dev.sh
cp    SunnyWalker/scripts/git_ca.sh my_new_project/scripts/git_ca.sh
cd my_new_project
```

(Or `git submodule add` if you prefer.)

## 2. Edit ONE file: `orchestrator/config.yaml`

```yaml
project:
  name: MyTauriApp
  description: "Cross-platform desktop X tool, Tauri 2 + React + Rust"

spec_path: docs/tauri_spec.md     # write your own spec
```

Adjust `milestones:` to your Day 1–N plan.

## 3. Replace `scripts/validate.sh`

The validator runs `bash scripts/validate.sh`. Replace its contents with
whatever validation makes sense for your project. Examples:

**Tauri:**
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
npm run build       || exit $?
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings
```

**Python:**
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
ruff check .
pytest -q
```

The validator agent just executes this script and parses pass/fail.

## 4. Write a spec

Create `docs/<spec_path>` (matching `config.yaml`) describing:
- Tech stack
- File structure
- Day-by-day milestones
- Code style
- Acceptance criteria

The Coder reads this; the Reviewer cross-references against it.

## 5. Run

```bash
./run.sh setup     # one-time
./run.sh next      # first run starts Day 1 with A
```

## What's project-agnostic vs project-specific

| Project-agnostic (don't edit) | Project-specific (edit per project) |
|---|---|
| `orchestrator/orchestrator.py` | `orchestrator/config.yaml` |
| `orchestrator/lib/*.py` | `scripts/validate.sh` |
| `orchestrator/prompts/*.md` | `docs/<spec>.md` |
| `run.sh` | `scripts/git_ca.sh` (only if branch policy differs) |
| `scripts/dev.sh` (mostly — adjust SCHEME / DESTINATION for non-iOS) | |

## What survives across projects

The framework is opinionated about:
- 4-agent ring (A → B → C → D → A)
- Append-only ring file as baton
- MAIN_ENTRY.md at root as resume manifest
- Heartbeat-based crash recovery
- Daily report auto-generation
- Auto-archive after day completes
- Tool-restricted agents (A can't git, B can't edit code, etc.)
- Token-limit detection in subprocess output

If you need different agent roles (say, 5 agents instead of 4), edit
`prompts/`, `config.yaml.agents`, and the dispatcher in `orchestrator.py`.
