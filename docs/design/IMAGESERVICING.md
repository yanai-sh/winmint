# Design: ImageServicing module

**Status:** **Accepted** (Design-it-twice + batch-grill 2026-07-28)  
**Module:** ImageServicing · **Owner:** `WinMint.Orchestrator` (call-out) · **Adapters:** `servicing/*.ps1`  
**Consumes:** `BuildArtifacts` · **Produces:** `ImageEvidence`  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md), [BUILDPLAN](BUILDPLAN.md), ADR-004, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)  
**Implements:** Smoke tickets 02, 09

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
    StageOobeUnattend,
    PatchBootWimApply,
    StampOfflineShell,
    StampOfflinePolicies, // product-constant + conditional HKLM stamps (ADR-009); after keep-flag, before payload
    RemoveProvisionedAppx, // keep-flag; after mount, before payload when Profile remove-list non-empty
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
4. First kernel non-zero → typed failure; workdir preserved (`logs/`, `failure.json`). **Leftover mounts discarded** (`%ProgramData%\WinMint\Servicing\{mount,boot-mount}` via DISM `/Discard`; legacy workdir mounts too) so a failed Apply does not leave an open WIM lock; media bytes stay for diagnosis.
5. Lane already encoded in `ExportWim` params by BuildPlan; manifest echoes lane.
6. **One elevated** `servicing/RunPlan.ps1` per `Apply` loops kernels (single UAC). RunPlan is a **dumb loop** — opcode → script map only; no product param injection.
7. **Materialize owns all Mutate params** (deepening map [Does Materialize own Mutate kind?](https://github.com/yanai-sh/winmint/issues/45)): for `RemoveCapabilities` / `DisableOptionalFeatures`, Materialize sets `kind=capability|feature` next to `mountDir` / `workDirectory`. Do not inject `kind` in RunPlan. Assert `kind` in S2 recording tests.
8. **Single-image WIM before commit (locked 2026-08-02):** `MountInstallWim` must leave `media/sources/install.wim` with **exactly one** index (export the planned edition out of a multi-edition consumer WIM first). `ExportWim` **fail-closes** if index count ≠ 1 before `Unmount /Commit`. Never commit a multi-edition `install.wim` in place — that path stalls DISM/`wimserv` for hours.
9. **Host mount root:** DISM mount points are `%ProgramData%\WinMint\Servicing\mount` (+ `boot-mount`), not under the workdir. Media/ISO/WIM stay in the workdir. Distinct from **guest** `%ProgramData%\WinMint\` durable tenure (checkpoint/heartbeat/evidence).
10. **WIM metadata discipline:** Snapshot `Get-WimInfo` (`Name`, `Architecture`, plus `Edition` / `Installation` / `ProductType` / `ProductSuite` / `Languages` when present; reject literal `<undefined>`) before multi-index export and before ResetBase/`Unmount /Commit`; re-assert after export, commit, and Release `/Compress:max`. Clear `install.wim` read-only before Export/Commit/max-export. After single-image WIM is ready: delete `sources\PID.txt` if present and write `sources\ei.cfg`; unattend pins `/IMAGE/INDEX=1`. Record under `logs/wim-metadata.json` + digest keys.

### Example stages (Test lane)

```
MountInstallWim → [RemoveProvisionedAppx?] → [RemoveCapabilities?] → [DisableOptionalFeatures?]
  → StampOfflinePolicies → StagePayload → StageOobeUnattend → StampOfflineShell → PatchBootWimApply
  → ExportWim(compression=fast, cleanup=skip) → BuildIso
```

`MountInstallWim` also: ISO→media copy, clear read-only, **single-index export** when needed, then DISM mount.  
`RemoveProvisionedAppx` (ticket **12**): optional; inventory → remove → re-inventory + Deprovisioned stamps; listed-but-absent ⇒ idempotent ok + `removed.appx.<id>=absent` ([KEEPFLAG](KEEPFLAG.md)).  
`StampOfflinePolicies` ([ADR-009](../decisions/ADR-009-product-constant-policies.md)): always; Plan emits `policySpecs` (EdgeDebloat + OneDrive + DeviceMetadata + WPBT; Copilot-kill iff `!keepCopilot`; BraveDebloat iff `Brave.Brave` in winget). Store MSIX host pwsh fails closed before Apply.  
`StageOobeUnattend` + `PatchBootWimApply`: WinPE apply lane (no legacy `InjectUnattend` / `setup.exe /legacy`).  
Release differs only in `ExportWim` params (`compression=max`, `cleanup=full`).

## Elevation model

| Model | Verdict |
|-------|---------|
| One UAC → `RunPlan.ps1` | **Recommended** |
| Per-kernel UAC | Rejected |

Unelevated `Apply`: preflight, materialize artifacts + resolved `stages.json` (all kernel params including Mutate `kind`), spawn elevated runner, parse evidence/failure.  
Elevated runner: dumb sequential invoke (no opcode→`kind` branching).

## What hides / what adapters do

**Hides:** opcode catalog, workdir layout, DISM/WIM/hive/oscdimg, Shell stamp hive paths, elevation spawn, digest assembly.

**Adapters:** thin `servicing/*.ps1` kernels. **Hard rule:** any Profile/DMA/SKU `if` in a kernel is an Architecture violation.

**Supervisor binary name:** `dotnet publish` emits `WinMint.Provisioning.exe`; Materialize / StagePayload copy it to guest path `Supervisor.exe` (`C:\Windows\WinMint\Supervisor.exe` Shell stamp). Intentional rename — do not “fix” the guest name back to the project assembly name.

**SetupComplete.cmd:** single source is repo [`payload/scripts/SetupComplete.cmd`](../../payload/scripts/SetupComplete.cmd); Materialize copies that file into the workdir payload (no embedded here-string).

## Dependencies

| Dep | Category |
|-----|----------|
| BuildArtifacts | In-process from BuildPlan |
| Source ISO + workdir | Local filesystem |
| Elevated pwsh + DISM/oscdimg | True external |
| Staged Supervisor binary | Materialize (repo payload/) |

## S2 test strategy

- Prefer fake elevated runner when introduced (same PR as port).
- Assert: stage order, Shell stamp path param, lane params; not ISO bytes.
- Kernels: no Profile branching (architecture violation if present).
- **WIM shape:** `MountInstallWim` exports multi-edition → single-image; `ExportWim` refuses commit unless index count = 1 (invariant 8). Metadata / ei.cfg / R/O clears (invariant 10); parser SelfCheck is unit-tested; real DISM proof is maintainer Apply.

## Ticket mapping

| Ticket | Focus |
|--------|-------|
| 02 | Mount/stage/export + offline Shell stamp + RunPlan elevation |
| 09 | Test vs Release export params honored + manifest lane |

## Explicitly rejected

v1 `WinMint.ps1` wrap; in-process DISM as default; Profile parsing in kernels; script paths in BuildPlan; per-stage UAC; **in-place `Unmount /Commit` of multi-edition consumer `install.wim`**.
