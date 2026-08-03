# Design: Keep-flag matrix (first vertical)

**Status:** **Accepted** (wayfinder map [Keep-flag matrix wayfinding](https://github.com/yanai-sh/winmint/issues/13), 2026-08-03)  
**Authority:** [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) · [BUILDPLAN](BUILDPLAN.md) · [IMAGESERVICING](IMAGESERVICING.md) · [PROVISIONINGSESSION](PROVISIONINGSESSION.md)  
**Implement:** after M1 ticket **10** green — stub cards in [TICKETS](../TICKETS.md)  
**Research:** [BCU](../research/2026-08-03-bulk-crap-uninstaller.md) · [offline DISM](../research/2026-08-03-offline-dism-remove-apis.md) · [AppX rehydrate](../research/2026-08-03-appx-rehydrate-after-oobe.md)

## Problem space

Users need a fail-closed way to strip selected **provisioned inbox AppX** from a Source ISO without a live uninstaller GUI, guest pwsh, or shipping third-party tools.

## Locked decisions

| Topic | Lock |
|-------|------|
| Polarity | **Remove-list only** |
| Presets in Profile | **None** (host/Wizard may expand to the list) |
| Kinds | **Provisioned AppX only** |
| Catalog | **Static shipped** in-repo; plan ⊆ catalog; image inventory for evidence |
| Schema | Optional remove-list on **`winmint.profile/v1`** (default empty) |
| Offline | **ImageServicing** primary — `Remove-AppxProvisionedPackage` / DISM `/Image`; `Deprovisioned` stamps when needed |
| FirstLogon | **ProvisioningSession** safety net — `PackageManager` remove; live deprovision only if still provisioned |
| Leftover confidence | **Deferred** past this vertical |
| BCU | **Do not ship** |

## Profile sketch (names illustrative until implement freezes JSON)

```json
{
  "schemaVersion": "winmint.profile/v1",
  "debloat": {
    "removeProvisionedAppx": ["Microsoft.BingNews", "Microsoft.GamingApp"]
  }
}
```

- Absent / empty `removeProvisionedAppx` ⇒ no removes (Smoke-compatible).
- Each entry must match a catalog id (package family name or catalog key — freeze at implement).
- Unknown id ⇒ plan document/plan failure (fail closed).

## Catalog

- Repo-owned static list of **legal** provisioned AppX identities for the remove-list (not “everything on a reference PC”).
- BuildPlan: validate remove-list ⊆ catalog; emit servicing stage params (package identities), never `.ps1` paths.
- ImageServicing: inventory mounted image (`Get-AppxProvisionedPackage`); remove listed present packages; record identity → final state in evidence; absent listed id ⇒ typed failure or documented no-op policy (freeze at implement — prefer fail-closed if Profile asserted remove).

## Seam mapping

```
Profile.remove list
    → BuildPlan validates + emits ServicingOpcode params
    → ImageServicing offline remove (+ optional Deprovisioned hive stamp)
    → (install / OOBE)
    → ProvisioningSession optional safety-net job (PackageManager)
```

### ImageServicing

- New opaque opcode (name freeze at implement), e.g. after mount / before or after payload stages — order freeze at implement.
- Kernels remain param-only; no Profile JSON branching.
- Evidence: re-inventory after removes; digests/logs per [offline DISM research](../research/2026-08-03-offline-dism-remove-apis.md).

### ProvisioningSession

- Optional job when remove-list non-empty: enumerate registered packages for the FirstLogon user; `RemovePackageAsync` for listed families still present; `DeprovisionPackageForAllUsersAsync` only if still provisioned.
- No guest pwsh; no UI Automation; no BCU.

## Explicitly deferred

- Capabilities / optional features in the matrix
- Schema `v2` bump
- Named Profile presets
- Confidence-tier leftover cleanup
- CDM / consumer-features policy as primary remove
- Wizard UX (M2 host; expands to the same remove-list)
- Default Pro ARM64 “recommended remove set” (fog — not locked here)

## Do not

- Bundle Bulk Crap Uninstaller
- Treat HKLM Uninstall inventory as the ISO source of truth
- Blind delete under `WindowsApps` as the primary path
