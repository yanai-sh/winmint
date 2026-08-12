# WinMint — Design (living)

**Phase:** Alpha — maintainer pick or new GitHub issue.  
**Product:** Windows 11 ISO builder. Host ARM64-first. Guest = **Provisioning Supervisor**.  
**Glossary:** [CONTEXT](../CONTEXT.md) · **Why greenfield:** [V1-LESSONS](design/V1-LESSONS.md) · **Shape:** [ARCHITECTURE](ARCHITECTURE.md)

**Invariant** = identity/safety. **Default** = shipped behaviour (change with spike). Everything else is issue-scoped, not living law.

## Modules

| Module | Doc |
|--------|-----|
| BuildPlan | [BUILDPLAN](design/BUILDPLAN.md) |
| ImageServicing | [IMAGESERVICING](design/IMAGESERVICING.md) |
| ProvisioningSession | [PROVISIONINGSESSION](design/PROVISIONINGSESSION.md) |

Cross-cuts (reference, not a frozen file set): [CONTRACTS](design/CONTRACTS.md) · [SECRETS](design/SECRETS.md) · [SPLASH](design/SPLASH.md) · [DEBLOAT](design/DEBLOAT.md)

## Invariants

1. User-supplied Source ISO only — no bundling or silent Windows media download
2. Provisioning Supervisor owns FirstLogon: splash-before-Explorer, DMA settle, unlock/reboot checkpoint, in-process splash — no guest **pwsh product runtime**, no peer Splash.exe, no v1 `WinMint.ps1`
3. Host Servicing: elevated `pwsh -File` kernels only (not in-process DISM from Cli/Wizard)
4. Debloat: remove-list only; no Profile preset names in JSON; CDM not primary
5. Residual self-erase after green Shell Complete; no dual `$OEM$` SetupScripts; tenure-only branded payload under `%WINDIR%\WinMint\`
6. Machine setup failure → non-zero exit (fail closed)
7. WIM: single-image commit; snapshot/assert Name/Arch/(Edition|Build) across export/commit
8. Stay on `winmint.profile/v1` until a real breaking change forces `v2`
9. Durable guest evidence/logs under `%ProgramData%\WinMint\`
10. Always-on product posture exists (offline policy stamps + fixed FirstLogon jobs) — **concrete ids live in code** / [ADR-009](decisions/ADR-009-product-constant-policies.md), not this list

## Defaults

- Lanes: `Test` | `Release` (run override). AppX debloat **online** by default; caps/features offline when listed. Install engine: WinPE apply only.
- Smoke: Local+autoLogon; DMA on acceptance Profiles; soft location warn/continue; fail-open unlock; stale heartbeat ⇒ fail-open.
- Packages: batch/delegate OK; curated installs best-effort + evidence unless strict requested.
- Secrets: prefer `passwordPath` / Wizard prompt. Host preset **`recommended`** expands → remove-list ids (never written as preset names).
- First paint: assert paint-before-settle order in S3; ≤2.0 s is a target, not a veto on GDI vs D2D.
- Flash: operator **Rufus DD Image** + SHA vs `digests.outputIso.sha256`; WinMint emits **Output ISO** only ([ADR-012](decisions/ADR-012-flash-outside-product-seam.md)).

## Acceptance

**Smoke:** Pro Hyper-V; Local+autoLogon; DMA on; splash before Explorer; DMA hard-field evidence; `Test` lane; reboot keeps Shell; pinned acceptance remove-list exercised. Maintainer `just smoke` on a real Source ISO — fixture S4 alone is not exit. Same Supervisor/settle/job executor as production. Detail: [Smoke](specs/2026-07-27-smoke.md).

**Primary:** Release-lane ISO from frozen `samples/sl7.profile.json` safe to wipe primary Surface Laptop 7 — Gate B (`just primary-gate` / `metal-acceptance.json`) → Flash (operator) → destructive install → FirstLogon + `--package-strict` green + evidence copied off-box. **Gate B alone does not meet Primary**; record wipe results in-repo when you have them. Do not gate Primary on a tracking issue. **Flash** and **restore** are operator hygiene, not WinMint downloads or disk writers ([ADR-012](decisions/ADR-012-flash-outside-product-seam.md)).

## Cold history

[decisions/](decisions/) ADRs · [research/](research/) · [specs/](specs/) · git history. Prefer this file over ADR bodies when they disagree.
