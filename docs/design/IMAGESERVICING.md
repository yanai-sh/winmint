# Design: ImageServicing module

**Module:** ImageServicing · **Owner:** Orchestrator call-out · **Adapters:** `servicing/*.ps1`  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md) · [BUILDPLAN](BUILDPLAN.md) · [DESIGN](../DESIGN.md)

## Role

Apply `BuildArtifacts` to a user-supplied Source ISO under elevation → `ImageEvidence`. Kernels are param-only (no Profile/`if`). Stages are opcodes from BuildPlan; ImageServicing maps opcode → script. Prefer one UAC per `Apply`.

## Interface

```csharp
namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public static Result<ImageEvidence, Failure> Apply(
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
    StageOobeUnattend,
    PatchBootWimApply,
    StampOfflineShell,
    StampOfflinePolicies,
    RemoveProvisionedAppx,
    ExportWim,
    BuildIso,
}
```

(Other Debloat opcodes as Plan emits.) Evidence: output ISO path, lane, Shell stamp path, digests.

## Invariants

1. Stages run in plan order; do not invent product stages.
2. BuildPlan emits opcodes + params — never repo-relative `.ps1` paths.
3. Kernels: parameter hashtables only — no Profile JSON.
4. First kernel non-zero → typed failure; workdir preserved; leftover mounts discarded.
5. Lane encoded in `ExportWim` params by BuildPlan.
6. One elevated `servicing/RunPlan.ps1` dumb loop per Apply (single UAC).
7. Materialize owns Mutate params (e.g. capability/feature `kind`) — not RunPlan.
8. Single-image WIM before commit; ExportWim fail-closes if index count ≠ 1.
9. Host mounts under `%ProgramData%\WinMint\Servicing\` — not under workdir.
10. WIM metadata snapshot/assert across export/commit/max-export; `ei.cfg` / INDEX=1 discipline.

## Typical stage order (Test)

`MountInstallWim` → Debloat removes? → `StampOfflinePolicies` → `StagePayload` → `StageOobeUnattend` → `StampOfflineShell` → `PatchBootWimApply` → `ExportWim` → `BuildIso`  
WinPE apply lane only. Release differs in `ExportWim` compression/cleanup params.

## Outside / rejected

Hides: DISM/WIM/hive/oscdimg, workdir layout, elevation spawn. Guest Supervisor path is `Supervisor.exe` (publish rename intentional). SetupComplete source: `payload/scripts/SetupComplete.cmd`.

Rejected: v1 `WinMint.ps1` wrap; in-process DISM as default; Profile in kernels; script paths in BuildPlan; per-stage UAC; in-place commit of multi-edition `install.wim`.
