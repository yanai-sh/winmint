# WinMint v2 — Roadmap

**Phase now:** Design Acceptance **signed** · Implementation **Released** ([TICKETS](TICKETS.md)).  
**Authority:** [ARCHITECTURE](ARCHITECTURE.md), [Smoke](specs/2026-07-27-smoke.md), ADRs, [design/](design/), [DESIGN](DESIGN.md).

## Milestones

| ID | Milestone | Destination | Status |
|----|-----------|-------------|--------|
| **D0** | Design-plan complete | Designs + roadmap + gate signed | **Done** (2026-07-28) |
| **M0** | Repo scaffold | Reserved `src/` builds | Present |
| **M1** | Smoke Hyper-V green | Profile → ISO → FirstLogon evidence | **Done** — maintainer Smoke prove-out (**14**) green 2026-08-04 |
| **M2** | Wizard | Second BuildPlan host; UI presets → remove-list | **Thin vertical done** (**15**, 2026-08-04); polish deferred |
| **M3** | Metal jobs / matrix expand | `winget` guest-proven (**16**); next **17** reboot-resume → **18** Scoop (metal exit); then keep-flag **19→20**; WSL deferred | After M2 |
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

Pro Smoke; Local+autoLogon; DMA on acceptance Profile; splash before Explorer; DMA hard evidence; `Test` lane; fail-open; reboot keeps Shell; pwsh-free guest; `%ProgramData%\WinMint\`; paint time recorded; **pinned acceptance AppX remove-list proven gone** ([ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) B4). **Prove-out:** maintainer `just smoke` on a real Source ISO (ticket **14**) — fixture S4 alone is not exit.

## M2–M4

Keep-flag AppX vertical (**11–13**) done; capabilities expand after metal milestone (**19** spike → **20** offline). Presets / CDM-as-primary / leftover confidence / product-default recommended set stay deferred ([KEEPFLAG](design/KEEPFLAG.md), [ADR-005](decisions/ADR-005-keep-flag-matrix.md), [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md)). Acceptance Profile carries a small frozen remove-list for M1 exit prove-out. Hardware = stricter evidence bars. No guest pwsh / settle forks / ISO Avalonia.
