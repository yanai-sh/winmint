# Design: Keep-flag matrix (first vertical)

**Status:** **Accepted** (wayfinder map [Keep-flag matrix wayfinding](https://github.com/yanai-sh/winmint/issues/13), 2026-08-03)  
**Authority:** [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) · [BUILDPLAN](BUILDPLAN.md) · [IMAGESERVICING](IMAGESERVICING.md) · [PROVISIONINGSESSION](PROVISIONINGSESSION.md)  
**Implement:** AppX vertical tickets **11–13** done; expansion deferred past Wizard ([ADR-006](../decisions/ADR-006-post-keepflag-sequencing.md))  
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
- ImageServicing: inventory mounted image (`Get-AppxProvisionedPackage`); remove listed present packages; record identity → final state in evidence; **absent listed id ⇒ fail closed** (typed kernel failure; Profile asserted remove — frozen ticket **12**).

## Seam mapping

```
Profile.remove list
    → BuildPlan validates + emits ServicingOpcode params
    → ImageServicing offline remove (+ optional Deprovisioned hive stamp)
    → (install / OOBE)
    → ProvisioningSession optional safety-net job (PackageManager)
```

### ImageServicing

- Opcode **`RemoveProvisionedAppx`** (frozen ticket **11**/**12**): after `MountInstallWim`, before `StagePayload`.
- Params: `packageFamilyNames` (semicolon-separated catalog ids) + `mountDir` (Materialize).
- Kernel: inventory → `Remove-AppxProvisionedPackage` → re-inventory; stamp `AppxAllUserStore\Deprovisioned\<PFN>`; digests `removed.appx.<id>=absent` + workdir `logs/`.
- Kernels remain param-only; no Profile JSON branching.

### ProvisioningSession

- Optional job **`appx.safetyNet`** (`keepflag.appx.safetyNet`) when remove-list non-empty (ticket **13**).
- Bundle carries `removeProvisionedAppx`; `jobs.json` carries kind (not hard-coded stub).
- Enumerate registered packages → `RemovePackageAsync`; `DeprovisionPackageForAllUsersAsync` only for families still provisioned.
- Port: `IAppxPackageManager` (S3 fake; production `WinRTAppxPackageManager`).
- No guest pwsh; no UI Automation; no BCU.

## Explicitly deferred (locked 2026-08-04 grill / ADR-006)

| Item | Lock |
|------|------|
| Capabilities / optional features | Separate vertical after Wizard; AppX-only until then |
| Schema `v2` | Stay on `winmint.profile/v1` until a breaking change forces bump |
| Named Profile presets | None in Profile (host/Wizard expands → list) — [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) |
| Confidence-tier leftover cleanup | Out of this product era — do not ticket |
| CDM / consumer-features as primary remove | Not primary; optional later hive stamp only |
| Wizard UX | M2 after maintainer Smoke (**14**); expands to same remove-list |
| Default / auto “recommended remove set” | **No** — curated catalog only; Smoke acceptance Profile stays empty remove-list |

## Do not

- Bundle Bulk Crap Uninstaller
- Treat HKLM Uninstall inventory as the ISO source of truth
- Blind delete under `WindowsApps` as the primary path
- Auto-on remove-list for acceptance Smoke
