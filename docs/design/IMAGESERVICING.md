# Design: ImageServicing module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28)  
**Module:** ImageServicing · **Owner:** `WinMint.Orchestrator` (call-out) · **Adapters:** `servicing/*.ps1`  
**Consumes:** `BuildArtifacts` · **Produces:** `ImageEvidence`  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md), [BUILDPLAN](BUILDPLAN.md), ADR-004, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)  
**Implements:** Smoke tickets 02, 07

## Problem space

Apply a planned artifact set to a user-supplied **Source ISO** under elevation, without recreating a Servicing product brain or leaking script paths into BuildPlan.

Constraints:

- Unelevated Orchestrator; elevated thin kernels only.
- Kernels **must not** branch on Profile / DMA / edition — parameters only.
- Stages are **opaque opcodes** from BuildPlan; ImageServicing maps opcode → script.
- Offline Shell stamp to Supervisor path (matches ProvisioningSession verify target).
- Image quality lane from plan (Test vs Release export params).
- One UAC per `Apply` preferred.
- Diagnosable workdir on failure; no silent partial success.
- No wrap of v1 `WinMint.ps1`.
- Port type only when a test fake ships in the same change.

## Designs considered (summary)

Minimize `Apply` now; introduce elevated-runner port only with a test fake. Input = in-memory `BuildArtifacts` (not plan-dir as the seam).

## Locked interface sketch

```csharp
namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public static Result<ImageEvidence, ServicingFailure> Apply(
        BuildArtifacts plan,
        ServicingRun run,
        CancellationToken ct = default);
}

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null);

public enum ServicingOpcode
{
    MountInstallWim,
    StagePayload,
    InjectUnattend,
    StampOfflineShell,
    ExportWim,
    BuildIso,
}

public sealed record ServicingStage(
    ServicingOpcode Opcode,
    IReadOnlyDictionary<string, string> Parameters);

public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);
```

### Invariants

1. Stages run in plan order; ImageServicing does not reorder or invent product stages.
2. BuildPlan emits opcodes + params; **never** repo-relative `.ps1` paths.
3. Kernels receive parameter hashtables only — no Profile JSON.
4. First kernel non-zero → typed failure; workdir preserved (`logs/`, `failure.json`).
5. Lane already encoded in `ExportWim` params by BuildPlan; manifest echoes lane.
6. **One elevated** `servicing/RunPlan.ps1` per `Apply` loops kernels (single UAC).

### Example stages (Test lane)

```
MountInstallWim → StagePayload → InjectUnattend → StampOfflineShell
  → ExportWim(compression=fast, cleanup=skip) → BuildIso
```

Release differs only in `ExportWim` params (`compression=max`, `cleanup=full`).

## Elevation model

| Model | Verdict |
|-------|---------|
| One UAC → `RunPlan.ps1` | **Recommended** |
| Per-kernel UAC | Rejected |

Unelevated `Apply`: preflight, materialize artifacts + resolved `stages.json`, spawn elevated runner, parse evidence/failure.  
Elevated runner: dumb sequential invoke.

## What hides / what adapters do

**Hides:** opcode catalog, workdir layout, DISM/WIM/hive/oscdimg, Shell stamp hive paths, elevation spawn, digest assembly.

**Adapters:** thin `servicing/*.ps1` kernels. **Hard rule:** any Profile/DMA/SKU `if` in a kernel is an Architecture violation.

## Dependencies

| Dep | Category |
|-----|----------|
| BuildArtifacts | In-process from BuildPlan |
| Source ISO + workdir | Local filesystem |
| Elevated pwsh + DISM/oscdimg | True external |
| Staged Supervisor binary | From plan.Payload |

## S2 test strategy

- Until fake: optional elevated integration (manual / maintainer).
- When fake lands: introduce `IElevatedPlanRunner` (or equivalent) **in the same PR**; assert stage order, Shell stamp path param, lane params — not ISO bytes.

## Ticket mapping

| Ticket | Focus |
|--------|-------|
| 02 | Mount/stage/export + offline Shell stamp + RunPlan elevation |
| 07 | Test vs Release export params honored + manifest lane |

## Explicitly rejected

v1 `WinMint.ps1` wrap; in-process DISM as default; Profile parsing in kernels; script paths in BuildPlan; per-stage UAC.
