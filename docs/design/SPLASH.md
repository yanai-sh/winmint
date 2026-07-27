# Splash / Shell tenure budgets

**Status:** Accepted (batch-grill 2026-07-28)  
**Authority:** V1-LESSONS (late splash), ADR-004 review trigger (AOT cold start), [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)

## Problem

v1 lost the “first paint” race to Explorer / light desktop. v2 puts Supervisor as Shell with in-process splash — still vulnerable if AOT+D2D init is slow or fail-open is late.

## Budgets (Smoke defaults — grill-locked)

| Metric | Budget | Measured where |
|--------|--------|----------------|
| **Time-to-first-paint** | ≤ **2.0 s** from Shell `Run` entry to first opaque splash frame | S4 harness; `FirstPaintBudget` for S3 **ordering** tests |
| Dwell / wall-clock / settle / stale | defaults per [PROVISIONINGSESSION](PROVISIONINGSESSION.md#smoke-defaults-grill-locked) | SessionPolicy + `%ProgramData%\WinMint\` heartbeat |
| **Machine setup** | Stamp+verify only; no long work | S3/S4 |

## Design requirements

1. **Paint before settle:** first splash frame precedes DMA poll (S3 asserts order).
2. **GDI fallback:** if Direct2D init fails, still show opaque branded frame if feasible; else fail-open sooner — no blank Shell.
3. **Crash fail-open:** heartbeat + stale checkpoint on next Shell start; unlock if abandoned.
4. **No peer Splash.exe.**

## Acceptance (S4)

- Splash was Shell UI before Explorer.
- Record measured time-to-first-paint; **warn** if over 2.0 s; **fail** if Explorer was first interactive UI or splash never appeared.

## Prototype spike

| Gate | Rule |
|------|------|
| Design Acceptance | **Waived** (budgets are targets) |
| Ticket **04** `ready-for-agent` | **Required** — throwaway “Supervisor as Shell + empty splash” VM; append measured cold-start to appendix below |

### Appendix — spike measurements

_None yet. Record date, host arch, AOT vs debug, ms to first paint._
