# Architecture review pass 3 (candidates 1–3)

**Date:** 2026-08-05  
**Status:** Approved (grilling)  
**Locks:** Act #1+#3 · Defer #2 · one commit on `dev` · trails in design docs (not ROADMAP)

## Decisions

| # | Candidate | Disposition | Ship |
|---|-----------|-------------|------|
| 1 | Smoke keep-flag pins | **Act** | `Invoke-Smoke.ps1` reads pins from `$Work/stages.json` by opcode; missing/unreadable ⇒ fail closed; Profile parse for guest creds only |
| 2 | Provisioning job `Kind` catalog | **Defer** | CONTRACTS footnote — revisit when next job kind lands |
| 3 | WizardProfileComposer / #48 | **Act** (overturn Defer) | `BuildPlan.SerializeProfile`; Wizard builds `Profile` → `Plan` + serialize; `IdList.FromMultiline`; delete `WizardProfileComposer` |

## Out of scope (not ROADMAP)

- Job Kind enum / shared catalog now
- Shared Contracts assembly
- Pins from `bundle.json` or Apply digests
- Keeping JSON round-trip through `TryParseProfile` for Wizard Plan

## Packaging

One session, one commit on `dev`.
