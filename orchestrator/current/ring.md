# Ring — agent baton

> Append-only handoff file between agents (A -> B -> C -> D -> A ...).
> Each agent: read entire ring, find last entry, do work, append exactly ONE entry,
> stamp `→ Hand off to <X>` or `→ End of Day N` at the end.
>
> Never edit past entries. To correct, append a new entry.

