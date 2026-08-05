# Design: Keep-flag matrix (first vertical)

**Status:** **Accepted** (wayfinder map [Keep-flag matrix wayfinding](https://github.com/yanai-sh/winmint/issues/13), 2026-08-03)  
**Authority:** [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) · [ADR-007](../decisions/ADR-007-cdm-not-primary.md) · [BUILDPLAN](BUILDPLAN.md) · [IMAGESERVICING](IMAGESERVICING.md) · [PROVISIONINGSESSION](PROVISIONINGSESSION.md)  
**Implement:** AppX **11–13** done; capabilities/features **19** spike → **20** offline done; Acceptance Wizard preset expands AppX + thin caps/features (**25**); product **`recommended`** host preset + KeepGaming (issue **56**). Lasting out: Profile presets-in-JSON, schema `v2`, leftover *product* cleanup ([ADR-006](../decisions/ADR-006-post-keepflag-sequencing.md)).

## Problem space

Users need a fail-closed way to strip selected **provisioned inbox AppX** from a Source ISO without a live uninstaller GUI, guest pwsh, or shipping third-party tools.

**Folded research conclusions (spent notes deleted):** BCU is live-only — borrow declarative list + catalog patterns; never ship BCU or leftover-confidence junk tiers. Offline remove surfaces are DISM `/Image` (or Dism `-Path`): provisioned AppX, capabilities, optional features — not host `/Online`. What looks like AppX “rehydrate” after OOBE is usually still-provisioned registration, missing `Deprovisioned` stamps, or consumer/CDM installs — hence ImageServicing primary + narrow FirstLogon safety-net, and CDM not primary ([ADR-007](../decisions/ADR-007-cdm-not-primary.md)).

## Locked decisions

| Topic | Lock |
|-------|------|
| Polarity | **Remove-list only** |
| Presets in Profile | **None** (host/Wizard may expand to the list) |
| Kinds | **Provisioned AppX** + **capabilities** + **optional features** (same remove-list polarity; separate catalogs) |
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
    "removeProvisionedAppx": ["Microsoft.BingNews", "Microsoft.BingWeather"],
    "removeCapabilities": ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
    "disableOptionalFeatures": ["WorkFolders-Client"]
  }
}
```

- Absent / empty `removeProvisionedAppx` ⇒ no removes (Smoke-compatible).
- Each AppX entry must match a catalog id (package family name or catalog key — freeze at implement).
- Unknown id ⇒ plan document/plan failure (fail closed).
- Capabilities / optional features: same remove-list polarity; Acceptance pins for prove-out; product **`recommended`** host expansion (issue 56) is separate and curated (catalog growth does not auto-expand it). Inventory media pin: **Windows 11 25H2 ARM64 English** Pro. Offline kernels: listed-but-absent / not-on-image ⇒ **ok + digest** (capabilities `Absent`, features `Disabled`) — not throw-on-missing.

### Thin acceptance pins (prove-out only — not a product default)

| Kind | Id |
|------|----|
| AppX | `Microsoft.BingNews`, `Microsoft.BingWeather` (Acceptance preset / sample) |
| Capability | `App.StepsRecorder~~~~0.0.1.0`, `WMIC~~~~` |
| Optional feature | `WorkFolders-Client` |

Re-pin if a future 25H2 English ARM64 ISO drops an id. Host SOT for expansion: `KeepFlagPresets.Acceptance` (below).

### Product `recommended` (issue 56 — host expansion SOT: `KeepFlagPresets.Recommended`)

Curated workstation strip. Catalog add does **not** auto-add here. Hard excludes (do not emit): Store, App Installer, Terminal, Camera, Photos, Edge foundations, MathRecognizer, print-related caps.

| Kind | Strip (unless KeepGaming for gaming rows) |
|------|-------------------------------------------|
| AppX | BingNews/Weather, GetHelp/Getstarted, OfficeHub, Solitaire, People, PowerAutomateDesktop, Todos, Alarms, FeedbackHub, Maps, YourPhone, ZuneMusic/Video, QuickAssist; GamingApp + Xbox.* unless KeepGaming |
| Capability | StepsRecorder, WMIC, VBSCRIPT, IE, PowerShell ISE, Wallpapers.Extended, WindowsMediaPlayer |
| Optional feature | WorkFolders-Client, WindowsMediaPlayer, TelnetClient, TFTP, SimpleTCP |

Keep overlays: **KeepGaming**, **KeepCopilot** (when false, recommended adds `Microsoft.Copilot` + Plan stamps Copilot-kill policies — [ADR-009](../decisions/ADR-009-product-constant-policies.md)). OneDrive uninstall + EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage are product constants (not AppX recommended-set).

## Catalog

- Repo-owned static list of **legal** provisioned AppX identities for the remove-list (not “everything on a reference PC”).
- BuildPlan: validate remove-list ⊆ catalog; emit servicing stage params (package identities), never `.ps1` paths.
- ImageServicing: inventory mounted image (`Get-AppxProvisionedPackage`); remove listed present packages; record identity → final state in evidence; listed-but-absent / already stripped ⇒ **idempotent ok + digest** (`removed.appx.<id>=absent`) — same reuse-media posture as capabilities/features (ticket **20**); do **not** throw-on-missing. (Ticket **12** early “fail closed on absent” wording overturned to match shipped `Remove-ProvisionedAppx.ps1`.)

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

### Catalog-id match (Offline vs live)

Same Profile catalog id; two adapters; **intentionally different fields** (DISM provisioned inventory ≠ WinRT package id):

| Seam | Matcher | Fields |
|------|---------|--------|
| ImageServicing `Remove-ProvisionedAppx` | `Test-PackageMatchesCatalogId` | `DisplayName` equality; `PackageName` prefix `id_` |
| ProvisioningSession safety-net | `WinRTAppxPackageManager.MatchesCatalogId` | `DisplayName` equality; `PackageFamilyName` / `PackageFullName` prefix `id_` |

S3 fakes must call production `MatchesCatalogId` (no copied predicate). Do **not** merge via a shared Contracts project; do **not** “align” Offline to live without a real mismatch bite.

## Explicitly out (lasting policy — ADR-005/006/007)

| Item | Lock |
|------|------|
| Schema `v2` | Stay on `winmint.profile/v1` until a breaking change forces bump |
| Named Profile presets | None in Profile (host/Wizard expands → lists) — [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) |
| Confidence-tier leftover *product* cleanup | **Out** — no product ticket; do not ship BCU / JunkManager tiers |
| CDM / consumer-features as primary remove | **Not primary** — [ADR-007](../decisions/ADR-007-cdm-not-primary.md) |
| Product-default **`recommended`** host preset | **Yes (issue 56)** — expands → Profile remove-list ids; never preset names in JSON; Cli empty lists stay empty outside Wizard default compose |
| Acceptance Smoke remove-list | **Yes (grill B4)** — small frozen list on acceptance Profile (AppX + thin caps/features; re-pin if media churn) |
| Acceptance pin SOT | **`KeepFlagPresets.Acceptance` expansion is host SOT** ([What is the single SOT for acceptance keep-flag pins?](https://github.com/yanai-sh/winmint/issues/46)). `samples/acceptance.profile.json` stays a concrete Profile fixture; one test asserts sample `debloat.*` equals that expansion. Preset names never in Profile JSON. |

## Shipped (no longer “deferred”)

| Item | Status |
|------|--------|
| Capabilities / optional features | Spike **19** + offline **20** |
| Wizard expands to remove-lists | **15** / **25** (Acceptance preset includes AppX + caps/features pins) |

## Do not

- Bundle Bulk Crap Uninstaller
- Treat HKLM Uninstall inventory as the ISO source of truth
- Blind delete under `WindowsApps` as the primary path
- Auto-inject a “recommended” remove-list into intentional empty Cli Profiles (Wizard/host compose expands; Profile remains the expanded list)
