# Design: Keep-flag

**Authority:** [DESIGN](../DESIGN.md) · [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) · [ADR-007](../decisions/ADR-007-cdm-not-primary.md)

**Identity:** remove-list only; no Profile preset names; CDM not primary; do not ship BCU / leftover-confidence as the control plane.

## Shape

Profile optional lists on `winmint.profile/v1` (default empty):

- `debloat.removeProvisionedAppx`
- `debloat.removeCapabilities`
- `debloat.disableOptionalFeatures`

Unknown catalog id ⇒ Plan fail-closed. Absent/empty ⇒ no removes. Host/Wizard presets (**`recommended`**, Acceptance) expand → ids; never write preset names into JSON. Copilot/gaming AppX are product-required via `ProductPosture` (always unioned at Plan/Compose).

**Offline (ImageServicing):** primary remove via DISM `/Image` (AppX / caps / features). Listed-but-absent ⇒ ok + digest. Kernels param-only.

**FirstLogon (ProvisioningSession):** optional `appx.safetyNet` when AppX remove-list non-empty — PackageManager remove; deprovision only if still provisioned. No guest pwsh; no UI Automation.

**Seam:** Profile list → BuildPlan validates + opcodes → ImageServicing offline → optional Shell safety-net.

## Catalog / matchers

Static in-repo catalogs. Offline matcher (DISM inventory fields) ≠ live matcher (WinRT fields) — same Profile id, two adapters; do not force-merge without a real mismatch.

Acceptance pins and **`recommended`** strip sets: host SOT in `KeepFlagPresets` (code). Acceptance Profile is a concrete fixture; re-pin if media drops an id.
