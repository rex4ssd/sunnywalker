# SunnyWalker Ring Process

> Single source of truth for the 4-agent pipeline (A→B→C→D→A→...).
> Append-only baton file. Each agent reads previous entries, does work,
> appends ONE entry, and stamps `→ Hand off to <next>` at the end.
>
> Never edit past entries. If something is wrong, append a new entry that corrects it.

## Reading guide for agents

When you start, scroll to the bottom and find the **last entry**.
- If it ends with `→ Hand off to <YOU>`, it's your turn.
- If it ends with `→ End of Day N`, you are the new Day N+1 starter (only A).
- If the last entry has `Status: IN_PROGRESS` of someone else → stop, do nothing.
- If the last entry has `Status: FAILED` → read the reason; if you can recover, append and try.

When you finish, append exactly one entry following the format below.

## Entry format

```
## [X] Day N — YYYY-MM-DD HH:MM:SS+08:00
Status: DONE | IN_PROGRESS | FAILED
Model:  <model name>

### What I did
- bullet
- bullet

### Files
+ added/path.swift
~ modified/path.swift

### Stamps
✅ <thing checked OK>
⚠️ <warning>
❌ <thing broken>

### For next (<Y> — <role>)
<concrete brief for next agent — what to do, where to look, what to expect>

→ Hand off to <Y>
```

For D's last entry of the day, replace `→ Hand off to <Y>` with `→ End of Day N`
and write the brief for tomorrow's A under "For next (A — Coder)".

---

