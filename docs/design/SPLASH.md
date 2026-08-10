# Splash / Shell tenure

**Authority:** [V1-LESSONS](V1-LESSONS.md) · [DESIGN](../DESIGN.md) · [PROVISIONINGSESSION](PROVISIONINGSESSION.md)

## Budgets

| Metric | Budget | Where |
|--------|--------|-------|
| Time-to-first-paint | ≤ 2.0 s target (Shell `Run` → first opaque frame) | S4 measures; S3 asserts **order** only |
| Dwell / settle / stale | [PROVISIONINGSESSION](PROVISIONINGSESSION.md) Smoke defaults | SessionPolicy + ProgramData heartbeat |
| Machine setup | Stamp+verify only | S3/S4 |

## Requirements

1. Paint before settle.
2. If Direct2D fails, still show opaque branded frame if feasible — else fail-open sooner (no blank Shell).
3. Crash/stale → fail-open on next Shell start.
4. No peer Splash.exe.

## Acceptance (S4)

Splash was Shell UI before Explorer. Warn if paint > 2.0 s; **fail** if Explorer was first interactive UI or splash never appeared.

## Harness notes (cold)

Prefer `efisys_noprompt.bin`; Pro generic setup key in unattend when needed; LabConfig if no vTPM; Hyper-V media ACL `NT VIRTUAL MACHINE\Virtual Machines:(R)`; Gen2 DVD attach; `OobeUnattend.xml` at ISO root (fallback) with primary copy to `Windows\Panther\unattend.xml` via StageOobeUnattend / LaunchApply; ARM64 oscdimg UEFI-only bootdata.
