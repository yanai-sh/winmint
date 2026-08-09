# Design: BuildPlan module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28) — design lock  
**Module:** BuildPlan · **Owner project:** `WinMint.Orchestrator`  
**Hosts:** `WinMint.Cli`, Avalonia `WinMint.Wizard` (ticket **15**)  
**Smoke ticket:** 01 (`validate`/`plan`; freeze Profile JSON names here)  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md), [CONTEXT](../../CONTEXT.md), [DESIGN](../DESIGN.md)

## Problem space

BuildPlan turns authored **Profile** intent plus per-run **RunOptions** into pure **artifacts** (unattend, job JSON, payload stage list, servicing stages, manifest). It is **in-process** (no DISM, no elevation). ImageServicing and ProvisioningSession consume artifacts later.

Constraints any interface must satisfy:

- Small surface; Cli and Wizard share one brain.
- Image quality is a **run override**, never a Profile field.
- DMA default-on → Ireland setup latch hidden inside the module.
- Local+autoLogon → password required (fail closed at plan time).
- Typed validation results; Microsoft-thin stack.
- No Servicing port inside BuildPlan.

## Designs considered (summary)

Design-it-twice: minimize (`TryParseProfile`+`Plan`) vs flexible `Execute(flags)` vs Validate/Plan/Write. **Locked:** minimize hybrid — pure entry points; structured validation issues + job discriminators from the flexible design; no `PlanIntent` soup; no day-one artifact sink port. Details archived in git history of this file if needed. **SerializeProfile** landed 2026-08-05 (overturn of issue #48 defer) as inverse of `TryParseProfile`.

## Locked interface sketch

```csharp
namespace WinMint.Orchestrator;

public static class BuildPlan
{
    public static Result<Profile, DocumentErrors> TryParseProfile(ReadOnlySpan<byte> utf8Json);
    // DocumentErrors stays — one-field wrapper; collapse rejected (unwrap tax ≠ reopen locked interface).

    public static byte[] SerializeProfile(Profile profile);
    // Inverse of TryParseProfile; omit empty packages/debloat (WhenWritingNull).

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null);
    // run null ⇒ ImageQuality.Test; IncludeSmokeStubs false (Smoke harness passes true)
}

public sealed record RunOptions
{
    public ImageQualityLane ImageQuality { get; init; } = ImageQualityLane.Test;
    public string? SourceIsoPath { get; init; }
    public string? OutputIsoPath { get; init; }
}

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,
    ServicingStageList Stages,   // opaque ServicingOpcode + params — NOT .ps1 paths
    DmaContract Dma,
    BuildManifest Manifest);
```

**Stages:** BuildPlan emits [`ServicingOpcode`](IMAGESERVICING.md) values + parameter maps. ImageServicing owns opcode → `servicing/*.ps1` resolution. See [CONTRACTS](CONTRACTS.md).

### Invariants (callers must know)

1. Pure / deterministic: same inputs → same artifacts (stable ordering for tests).
2. No I/O inside `Plan` / `TryParseProfile` / `SerializeProfile`.
3. Failure ⇒ no partial artifacts.
4. Image quality only from `RunOptions` (encoded into `ExportWim` stage params).
5. DMA enabled (default) ⇒ Ireland latch in unattend **and** settle targets in `DmaContract`.
6. Local+autoLogon ⇒ non-empty password or `PlanFailure` ([SECRETS](SECRETS.md)).
7. Ordering for hosts: build or parse Profile → `Plan` → optional `SerializeProfile` for export → host may write files → ImageServicing.Apply.
8. No repo-relative script paths in artifacts.

### Error modes

- Document errors: schema/JSON/field shape.
- Plan failures: semantic + run-option errors (`account.password.required`, …).
- Exceptions: bugs only.

## What stays outside the seam

- File read/write of Profile and artifacts (Cli adapter).
- Source ISO existence checks (host or pre-Servicing).
- Elevated DISM / hive / oscdimg (ImageServicing).
- Splash / settle / jobs execution (ProvisioningSession).
- Host multiline id lists (`IdList.FromMultiline`) — UI/text helper, not Profile domain.
- Cli human plan dump (`WritePlanArtifacts` untyped JSON) vs ImageServicing Materialize `*File` serializers — **defer** merging until the next StageParams / artifact field change (same trigger class as serialize drift). CONTRACTS allows the dump; twin serializers are accepted debt until then.

## Ticket 01 TDD tracers (first vertical slices)

Work **one failing test → minimal green** at a time:

1. Empty/invalid JSON → document error.
2. Missing password on Local+autoLogon → plan failure.
3. DMA on → unattend contains Ireland setup locales; `DmaContract` has settle target from Profile.
4. Default `Plan(profile)` → manifest lane = Test; no `smoke.stub.*` unless `IncludeSmokeStubs`.

**Ticket 09 (not 01):** Explicit `ImageQuality.Release` → `ExportWim` stage/export params differ from Test (BUILDPLAN owns lane field parse in 01; export param values are 09).

## Open points (closed in ticket 01)

- Profile JSON field names / `schemaVersion` **frozen**: `winmint.profile/v1` with `account.mode|username|password`, optional `account.requireWifiDuringOobe` (default **true** → show OOBE Network; Smoke sets `false`), `dma.enabled|settle.{locale,geoId,timeZoneId,locationServicesEnabled}`; account mode string `localAutoLogon`. Optional `debloat.removeProvisionedAppx` (ticket 11). Optional `debloat.removeCapabilities` / `debloat.disableOptionalFeatures` (ticket 20 — catalog-validated; opcodes after AppX remove, before StagePayload; digests `removed.capability.<id>=Absent` / `disabled.feature.<id>=Disabled`). Optional `packages.winget: string[]` (ticket 16 — empty/absent ⇒ no package jobs; each id ⇒ `jobs.json` entry `kind: "winget"`, `packageId`, `id: winget.<id>`; `smoke.stub.*` only when `RunOptions.IncludeSmokeStubs`). Optional `packages.wingetNeedsReboot: string[]` (ticket 17 — must be a subset of `packages.winget`; matching jobs get `needsReboot: true`; unknown id ⇒ Plan fail-closed `packages.wingetNeedsReboot.unknown`). Optional `packages.scoop: string[]` + `packages.scoopNeedsReboot: string[]` (ticket 18 — same subset rules; jobs `kind: "scoop"`, `id: scoop.<id>`; FirstLogon bootstrap = official ScoopInstaller admin one-liner via inbox `powershell.exe` — see [PROVISIONINGSESSION](PROVISIONINGSESSION.md)). Optional `packages.wsl: string[]` + `packages.wslNeedsReboot: string[]` (ticket 23 — store install or catalog `fromFile`; see [spec](../specs/2026-08-05-package-catalog-arm64.md)). **Package catalog** ([ADR-010](../decisions/ADR-010-arm64-package-policy.md)): `config/packages.json` embedded; Plan validates ids (`packages.catalog.*`); arm64 winget jobs get `wingetArchitecture`; non-empty winget on arm64 ⇒ `package.auditNative`. Autounattend OOBE: always `HideOnlineAccountScreens=true` + local `UserAccounts`/`AutoLogon`; `HideWirelessSetupInOOBE` = invert of `requireWifiDuringOobe` (official Unattend lever — show Network when false/omit; Smoke sets hide). Do not use BypassNRO / LabConfig / SkipMachineOOBE for this contract.
- C# DTOs + source-gen = source of truth; no `schemas/*.json` yet.
- Secrets: follow [SECRETS](SECRETS.md) (already grill-locked).
