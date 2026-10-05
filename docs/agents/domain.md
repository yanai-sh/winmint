# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root (glossary — coined terms, polarity, avoid-lists)
- **`docs/decisions/`**: read ADRs that touch the area you're about to work in
- **`AGENTS.md`**: map only — which tree to open; not living design law

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill creates glossary/ADR material lazily when terms or decisions actually get resolved — in this repo that means updating `CONTEXT.md` / `docs/decisions/`, not inventing a parallel `GLOSSARY.md` or `docs/adr/`.

## File structure

Single-context:

```
/
├── CONTEXT.md
├── AGENTS.md
├── docs/decisions/
│   ├── ADR-001-….md
│   └── …
└── src/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids (`_Avoid_:` lines).

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-014 (docs are not living law), but worth reopening because…_
