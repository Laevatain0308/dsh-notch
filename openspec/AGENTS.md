# OpenSpec instructions

This project uses OpenSpec to record what Notch's behaviour is, and what it is proposed to become. Read [project.md](project.md) first.

## Where things go

```
openspec/
├── project.md                        # context, architecture, scope
├── AGENTS.md                         # this file
├── specs/<capability-path>/spec.md   # what is BUILT
└── changes/<change-name>/
    ├── proposal.md                   # why, what, impact
    ├── design.md                     # technology decisions and reasoning
    ├── tasks.md                      # implementation checklist
    └── specs/<capability-path>/spec.md  # deltas: ADDED / MODIFIED / REMOVED / RENAMED
```

`specs/` is the current truth and is **empty until something is actually built**. A proposal never edits `specs/` directly; it carries deltas under its own `specs/` and those are applied when the change is archived.

## Writing a spec

- `### Requirement: [Name]` — under 50 characters, immediately followed by a `SHALL` statement stating the core behaviour.
- `#### Scenario: [Description]` — bullet steps using the bold keywords `**GIVEN**` (optional), `**WHEN**`, `**THEN**`, `**AND**`.
- Requirement headers are identifiers. They must be unique within a spec and are matched case-sensitively after trimming, so renaming a requirement is an explicit `## RENAMED Requirements` operation.
- A delta for a capability that has no spec yet opens with `## Purpose`, which seeds that spec.

## The behaviour-first boundary

Specs capture **externally observable behaviour**: interfaces, state transitions, error handling, limits, and constraints — the things a provider or a user can verify.

Anything about *how* it is done belongs elsewhere:

| Belongs in a spec | Belongs in `design.md` / `tasks.md` |
| --- | --- |
| Which states an entity may be in | The wire message names and schema shape |
| That registration requires explicit user consent | The consent window's implementation, transport, and storage |
| That the display shows one expandable entity at a time | The arbitration scoring function |
| That a motion exists for a state transition, and what happens without one | How the motion library is authored, keyed, and rendered |
| That a provider's entities expire without renewal | The heartbeat interval and transport |

## Specific to Notch

Two rules that decide most disputes:

1. **No provider knowledge in Core.** If a requirement can only be satisfied by recognising a particular provider, it is wrong — restate it in terms of the behaviour pattern it belongs to.
2. **Motion is behaviour, not decoration.** A requirement that a transition animates, and the fallback when no motion fits, is spec material. The curves and keyframes are not.

Also record **limits** explicitly (how many providers, entities, concurrent interactions, how long a lease is). An ecosystem without stated bounds produces unbounded UI.
