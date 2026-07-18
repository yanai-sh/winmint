# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, if it exists.
- **`docs/decisions/`** — read ADRs that touch the area you're about to work in. This repo uses `docs/decisions/` (not `docs/adr/`) for architectural decisions.
- **WinMint v2 greenfield:** planning lives under [`docs/v2/`](../v2/README.md). The tree to copy into the new repo is [`docs/v2/seed-for-new-repo/`](../v2/seed-for-new-repo/).

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/decisions/
│   ├── ADR-001-gpui-to-webview2-wizard.md
│   ├── ADR-002-dual-setup-shell-hosts.md
│   └── ...
└── src/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-007 (package-source-policy) — but worth reopening because…_
