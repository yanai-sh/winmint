# WinMint v2 (planning in the v1 repo)

| Path | Role |
|------|------|
| [`seed-for-new-repo/`](seed-for-new-repo/) | Tree that becomes the **winmint-v2 initial commit**. How to copy/push: [`COPY-INTO-NEW-REPO.md`](COPY-INTO-NEW-REPO.md). |
| [`roadmap.md`](roadmap.md) | Legacy living roadmap (v1 + early v2 drafts). Prefer ADR-011 + the seed for v2 scope. |
| [`coding-contract.md`](coding-contract.md) | Stub → seed coding contract |
| [`migration-guide.md`](migration-guide.md) | Stub → seed architecture / workflow |

**Accepted decisions in this repo:** [ADR-010](../decisions/ADR-010-source-iso-legal.md), [ADR-011](../decisions/ADR-011-winmint-v2-greenfield.md).

**Do not** treat ADR-011 as a license to rewrite v1 in place.

## Keeping the seed honest

When v1 lands Smoke-critical or durable product posture changes, update:

1. [`seed-for-new-repo/docs/PORT-FROM-V1.md`](seed-for-new-repo/docs/PORT-FROM-V1.md) — harvest paths  
2. [`seed-for-new-repo/docs/ARCHITECTURE.md`](seed-for-new-repo/docs/ARCHITECTURE.md) + [`AGENTS.md`](seed-for-new-repo/AGENTS.md) / [`CONTEXT.md`](seed-for-new-repo/CONTEXT.md) — invariants and vocabulary  
3. [`roadmap.md`](roadmap.md) — v1 track status only when it changes what v2 should steal or avoid  

**Last sync:** 2026-07-20 — Autologon stamp, splash stages/a11y, Edge-keep, Coreutils, WSL conf, device-metadata block, Max-cache/PE-driver/undo harvest, Raycast/Everything cut.
