# WinMint v2 — Roadmap

**Phase now:** Design Acceptance **signed** · Implementation **Released** ([TICKETS](TICKETS.md)).  
**Authority:** [ARCHITECTURE](ARCHITECTURE.md), [Smoke](specs/2026-07-27-smoke.md), ADRs, [design/](design/), [DESIGN](DESIGN.md).

## Milestones

| ID | Milestone | Destination | Status |
|----|-----------|-------------|--------|
| **D0** | Design-plan complete | Designs + roadmap + gate signed | **Done** (2026-07-28) |
| **M0** | Repo scaffold | Reserved `src/` builds | Present |
| **M1** | Smoke Hyper-V green | Profile → ISO → FirstLogon evidence | **In progress** — next card **14** (maintainer Smoke); stack **01–13** done |
| **M2** | Wizard | Second BuildPlan host; UI presets → remove-list | After **14** ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)) |
| **M3** | Metal jobs / matrix expand | First metal kind `winget`; keep-flag expand only after Wizard | After M2 (or after **14** if Wizard deferred by rescope) |
| **M4** | Hardware acceptance | Stricter evidence bars; same Supervisor/settle/jobs | After M2/M3 |

## Design Acceptance

| Field | Value |
|-------|-------|
| Date | **2026-07-28** |
| Maintainer | Project owner (batch-grill shared understanding) |
| Splash prototype | Waived for gate; required before ticket **04** |
| Notes | Grill locks: [DESIGN](DESIGN.md#decisions-locked-grill). Quality pass: canonical backlog [TICKETS](TICKETS.md). Post–keep-flag sequencing: [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) (2026-08-04). |

## M1 order

Canonical ticket cards + DoD: **[TICKETS](TICKETS.md)**. Do not duplicate tables elsewhere.

## M1 exit criteria

Pro Smoke; Local+autoLogon; DMA on acceptance Profile; splash before Explorer; DMA hard evidence; `Test` lane; fail-open; reboot keeps Shell; pwsh-free guest; `%ProgramData%\WinMint\`; paint time recorded. **Prove-out:** maintainer `just smoke` on a real Source ISO (ticket **14**) — fixture S4 alone is not exit.

## M2–M4

Wizard = second BuildPlan host. Keep-flag AppX vertical (**11–13**) done; expansion (capabilities, presets, CDM-as-primary, default remove set) deferred past Wizard ([KEEPFLAG](design/KEEPFLAG.md), [ADR-005](decisions/ADR-005-keep-flag-matrix.md), [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)). Hardware = stricter evidence bars. No guest pwsh / settle forks / ISO Avalonia.
