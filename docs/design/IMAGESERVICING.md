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
    public static Task<Result<ImageEvidence, Failure>> ApplyAsync(
        BuildArtifacts plan,
        ServicingRun run,
        IElevatedPlanRunner runner,
        CancellationToken ct = default);
}

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null,
    string? ProfilePath = null,
    int? WimIndex = null,
    bool ReuseMedia = false,
    string? SourceIsoSha256 = null,
    SelectedWim? SelectedImage = null);

/// <summary>Elevation only — evidence read is ImageServicing implementation.</summary>
public interface IElevatedPlanRunner
{
    Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
        string workDirectory,
        CancellationToken ct);
}
```

The stage list crosses this seam as `{workDirectory}/stages.json` — Materialize writes it, `Invoke-ServicingPlan.ps1` reads it. An adapter that also took stages in-process would be a second, unenforced copy of the contract.

HostCompile resolves and freezes the build Output ISO path before Apply. The lower-level ImageServicing entry retains its default-name fallback for direct S2 callers, but HostCompile composition never relies on it. Materialize and evidence use the supplied path unchanged. Elevated `Invoke-ServicingPlan.ps1` is the hard seam; reading `evidence.json` into `ImageEvidence` stays inside ImageServicing.

`MountInstallWim` receives the frozen Source ISO hash and selected-image metadata. `ReuseMedia=false` always recreates staged media. `ReuseMedia=true` requires an exact `winmint.media-identity/v1` marker plus matching staged single-image WIM metadata; absent, malformed, or mismatched identity takes the cold recreate path and writes the marker atomically after validation.

**Elevated plan loop:** opcode kernels mutate media only. The loop alone finalizes host Apply state — `Write-PlanEvidence` after all kernels succeed, `Write-PlanFailure` on any throw or non-zero kernel exit. Kernels do not write `evidence.json` or `failure.json`. **`BuildIso`** runs `oscdimg` and emits the **Output ISO** only; digest and evidence assembly happen in the loop after `BuildIso` returns.

**Stale evidence / failure ordering:** each Apply run removes stale `evidence.json` at start (prior `failure.json` stays visible until overwritten or cleared). Reusing a workdir therefore clears prior green evidence when the new run starts; use a fresh workdir to retain certifiable prior output. On failure the loop removes stale evidence, writes current `failure.json`, and sets `apply-status.txt` to failed. On success it writes fresh `evidence.json` (Output ISO digest last), then removes `failure.json`. Evidence is not green while a stale failure file remains.

## Kernel naming

A kernel file is named for the opcode it serves: `ServicingOpcode.StampOfflinePolicies` → `servicing/Stamp-OfflinePolicies.ps1`. That one-to-one mapping outranks PowerShell's approved-verb list, so `Stamp-`, `Stage-`, `Patch-` and `Inject-` stay. Everything in `servicing/` that is **not** an opcode kernel is a helper and does take an approved verb — `Invoke-ServicingPlan.ps1` (the loop), `Get-WimMetadata.ps1` (dot-sourced parser). `Set-OfflineComponent.ps1` serves two opcodes (`RemoveCapabilities`, `DisableOptionalFeatures`) and so cannot take either name.

## Invariants

1. Stages run in plan order; do not invent product stages.
2. BuildPlan emits opcodes + params — never repo-relative `.ps1` paths.
3. Kernels: parameter hashtables only — no Profile JSON.
4. First kernel non-zero → typed failure; workdir preserved; leftover mounts discarded.
5. Lane encoded in `ExportWim` params by BuildPlan.
6. One elevated `servicing/Invoke-ServicingPlan.ps1` dumb loop per Apply (single UAC).
7. Materialize owns Mutate params (e.g. capability/feature `kind`) — not the kernel loop.
8. Single-image WIM before commit; ExportWim fail-closes if index count ≠ 1.
9. Host mounts under `%ProgramData%\WinMint\Servicing\` — not under workdir.
10. WIM metadata snapshot/assert across export/commit/max-export; `ei.cfg` / INDEX=1 discipline.

## Typical stage order (Test)

`MountInstallWim` → `StampOfflinePolicies` → Debloat removes? → capability/feature removes? → `InjectDrivers`? → `StagePayload` → `StageOobeUnattend` → `StampOfflineShell` → `PatchBootWimApply` → `ExportWim` → `BuildIso`  
Policies stamp first: creating new `Policies\Microsoft\*` keys flakes Unauthorized on a heavily-serviced mount.
WinPE apply lane only. Release differs in `ExportWim` compression/cleanup params.

### WinPE apply launcher

Authoritative launcher: `payload/winpe/LaunchApply.cmd`. `PatchBootWimApply` byte-copies it into `Windows\System32\LaunchApply.cmd` and stamps `winpeshl.ini` across **every** `boot.wim` index (skip only when marker + all indexes match). `WinPeApplyContract.ps1` is the single definition for patch skip/re-patch and Gate B assert — byte identity, `/Index:1` apply target, disk guard, and `winpeshl.ini` launch line. Do not embed launcher content in kernels; edit the payload file.

### Target disk

`LaunchApply.cmd` runs `clean` with no operator present, so the erase target is **discovered, never hardcoded** — disk 0 can be the USB it booted from. It keeps disks whose `detail disk` `Type` is not USB, then erases the single survivor. Two survivors is where a size heuristic guesses wrong, so it **refuses and prints the list** instead. So does zero survivors, or unparsable output.

The escape hatch for a genuinely ambiguous machine is a unique model substring in `winmint-target-disk.txt` at the media root — operator hygiene on already-writable media, not a Profile field, since the value identifies one machine's hardware rather than a reusable build intent. It narrows candidates and cannot select a USB.

Branches are proven in [Test-DiskGuard](../../tests/contract/Test-DiskGuard.ps1) against pre-seeded `diskpart` output, since WinPE cannot be exercised from a dev box.

## Outside / rejected

Hides: DISM/WIM/hive/oscdimg, workdir layout, elevation spawn. Guest Supervisor path is `Supervisor.exe` (publish rename intentional). SetupComplete source: `payload/scripts/SetupComplete.cmd`.

Rejected: v1 `WinMint.ps1` wrap; in-process DISM as default; Profile in kernels; script paths in BuildPlan; per-stage UAC; in-place commit of multi-edition `install.wim`.
