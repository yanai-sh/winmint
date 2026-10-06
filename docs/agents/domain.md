# Domain docs

How engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- **`CONTEXT.md`** — coined terms, polarity, avoid-lists
- **`docs/decisions/`** — ADRs that touch the area you're about to work in
- **`AGENTS.md`** — map only (which tree to open); not living design law

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. `/domain-modeling` updates `CONTEXT.md` / `docs/decisions/` lazily when terms or decisions resolve — never invent a parallel `GLOSSARY.md` or `docs/adr/`.

## Use the glossary's vocabulary

When output names a domain concept (issue title, refactor proposal, hypothesis, test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids (`_Avoid_:` lines).

If the concept isn't in the glossary yet: either you're inventing language the project doesn't use (reconsider), or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-014 (docs are not living law), but worth reopening because…_
