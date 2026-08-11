# Spec: FU-durable quiet / debloat posture

**Date:** 2026-08-11  
**Plan:** `.cursor/plans/fu_durable_posture_744acaec.plan.md`  
**Authority:** [ADR-007](../../decisions/ADR-007-cdm-not-primary.md) · [ADR-009](../../decisions/ADR-009-product-constant-policies.md) · [DEBLOAT](../../design/DEBLOAT.md) · [ADR-008](../../decisions/ADR-008-residual-minimization.md)

## Problem Statement

Feature updates can rehydrate consumer suggestion surfaces and reintroduce AppX that WinMint removed. Curated wipe posture must survive FU via durable Windows state — not a live WinMint agent (ADR-008) and not WU deferral.

## Solution

Approach **(1)** only:

1. Product-constant offline **HKLM** policies: CloudContent consumer features + Store AutoDownload (suggested apps), alongside existing Widgets/Edge/OneDrive.
2. **Deprovisioned** PFN marks: offline readback assert after stamp; online `appx.safetyNet` verify/stamp if WinRT left the mark missing.
3. Keep HKCU in `workstation.quiet`; no CDM DWORD spray as primary.

Default User hive stamp deferred.

## Product locks

| Lock | Value |
|------|--------|
| Survive FU | Durable HKLM + AppX Deprovisioned |
| Updates | Never delay/block WU or Insider |
| CDM | HKLM CloudContent **policy** OK as product-constant; per-user CDM not primary |
| Residual | No live re-assert; erase after Complete |

## HKLM keys (always)

| Subkey | Name | Data |
|--------|------|------|
| `Policies\Microsoft\Windows\CloudContent` | `DisableWindowsConsumerFeatures` | `1` |
| `Policies\Microsoft\Windows\CloudContent` | `DisableSoftLanding` | `1` |
| `Policies\Microsoft\WindowsStore` | `AutoDownload` | `2` |

## Non-goals

- WU deferral / Insider blocking  
- Live assert-posture CLI / scheduled task  
- Default User `NTUSER.DAT` stamp  
- HKCU ContentDeliveryManager as primary remove engine  

## Testing

- Plan policy specs contain the three keys; QuietLabels updated.
- Offline AppX: missing Deprovisioned after write ⇒ fail.
- Online safety-net: stamps Deprovisioned when missing; tests with fakes.

## Success

After FU on a Primary-like image: Widgets/consumer suggestions stay suppressed and remove-list AppX stay deprovisioned without any WinMint process remaining.
