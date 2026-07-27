# Design: BuildPlan module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28) — design lock  
**Module:** BuildPlan · **Owner project:** `WinMint.Orchestrator`  
**Hosts:** `WinMint.Cli` (now), Avalonia Wizard (later)  
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

Design-it-twice: minimize (`TryParseProfile`+`Plan`) vs flexible `Execute(flags)` vs Validate/Plan/Write. **Locked:** minimize hybrid — two pure entry points; structured validation issues + job discriminators from the flexible design; no `PlanIntent` soup; no day-one artifact sink port. Details archived in git history of this file if needed.

## Locked interface sketch

```csharp
namespace WinMint.Orchestrator;

public static class BuildPlan
{
    public static Result<Profile, DocumentErrors> TryParseProfile(ReadOnlySpan<byte> utf8Json);

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null);
    // run null ⇒ Smoke defaults (ImageQuality.Test; SourceIsoPath may be empty until servicing)
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
    PayloadManifest Payload,
    ServicingStageList Stages,   // opaque ServicingOpcode + params — NOT .ps1 paths
    DmaContract Dma,
    BuildManifest Manifest);
```

**Stages:** BuildPlan emits [`ServicingOpcode`](IMAGESERVICING.md) values + parameter maps. ImageServicing owns opcode → `servicing/*.ps1` resolution. See [CONTRACTS](CONTRACTS.md).

### Invariants (callers must know)

1. Pure / deterministic: same inputs → same artifacts (stable ordering for tests).
2. No I/O inside `Plan` / `TryParseProfile`.
3. Failure ⇒ no partial artifacts.
4. Image quality only from `RunOptions` (encoded into `ExportWim` stage params).
5. DMA enabled (default) ⇒ Ireland latch in unattend **and** settle targets in `DmaContract`.
6. Local+autoLogon ⇒ non-empty password or `PlanFailure` ([SECRETS](SECRETS.md)).
7. Ordering for hosts: parse (if JSON) → `Plan` → host may write files → ImageServicing.Apply.
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

## Ticket 01 TDD tracers (first vertical slices)

Work **one failing test → minimal green** at a time:

1. Empty/invalid JSON → document error.
2. Missing password on Local+autoLogon → plan failure.
3. DMA on → unattend contains Ireland setup locales; `DmaContract` has settle target from Profile.
4. Default `Plan(profile)` → manifest lane = Test; stub jobs present.
5. Explicit `ImageQuality.Release` → stage/export params differ from Test.

## Open points (ticket 01)

- Exact Profile JSON field names / `schemaVersion` string (freeze in 01).
- C# DTOs + source-gen = source of truth; optional `schemas/*.json` only if generated or clearly secondary.
- Secrets: follow [SECRETS](SECRETS.md) (already grill-locked).
