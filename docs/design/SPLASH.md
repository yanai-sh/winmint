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

Date: 2026-07-29 (host: Windows on ARM64, native; guest: Arm64)

Build: Release **NativeAOT** (`SplashSpike.exe`), no debug.

Time-to-first-paint (Shell `Run` entry → first opaque frame):

| cold boot # | ms to first painted frame |
|---:|---:|
| 1 | 1173 ms |
| 2 | 391 ms |
| 3 | 104 ms |

Fresh unattended cycle replay (new VHD + reinstall, same host, same Release NativeAOT spike):

| cold boot # | ms to first painted frame | ordering probe |
|---:|---:|---|
| 1 | 259 ms | `first frame painted` logged before separate-process `settle probe start` |
| 2 | 140 ms | `first frame painted` logged before separate-process `settle probe start` |
| 3 | 94 ms | `first frame painted` logged before separate-process `settle probe start` |

Reliability posture (before ticket **04** treats this as “green”):
- This is still a **prototype spike**, not the product acceptance harness; however, the throwaway runner now covers both **repeatability across a fresh unattended cycle** and a minimal **paint-before-settle** ordering proof.
- It still does **not** prove the real ticket **04** presenter/evidence path end-to-end. The remaining hardening is to run the actual product-side presenter and evidence projection once hold lifts.

### Appendix — host / VM lessons (for tickets 02 / 10)

Throwaway spike ops under `.scratch/splash-spike/` (not product code). Carry these into Servicing unattend/ISO rebuild and the S4 harness:

| Lesson | Detail |
|--------|--------|
| Prefer `efisys_noprompt.bin` | `efisys.bin` leaves Gen2 VMs on “Press any key to boot from CD or DVD…” and install never starts |
| Pro generic setup key | Unattend `UserData/ProductKey` = `VK7JG-NPHTM-C97JM-9MPGT-3V66T` skips the key page (does not activate); omit ⇒ Setup blocks |
| LabConfig when no vTPM | Host `Start-VM` may fail with TPM enabled; patch `boot.wim` LabConfig (`BypassTPMCheck` / `BypassSecureBootCheck` / `BypassRAMCheck`) for install media used without vTPM |
| Hyper-V media ACLs | After rewriting an ISO/VHD, grant `NT VIRTUAL MACHINE\Virtual Machines:(R)` or Start-VM returns Access Denied |
| Attach DVD explicitly | Gen2 may need `Add-VMDvdDrive` after recreate; empty DVD path ⇒ UEFI “boot loader failed” |
| Autounattend at ISO root | Answer file on install ISO root is enough; second unattend ISO is optional |
| ARM64 oscdimg bootdata | UEFI-only: `1#pEF,e,b<path-to-efisys>` (no legacy BIOS sector) |

Spike bar for ticket **04** `ready-for-agent`: timing + ordering + one fresh-cycle replay — **met** (2026-07-29).
