# Design: BuildPlan module

**Module:** BuildPlan · **Owner:** `WinMint.Orchestrator` · **Hosts:** Cli, Wizard  
**Authority:** [ARCHITECTURE](../ARCHITECTURE.md) · [CONTEXT](../../CONTEXT.md) · [DESIGN](../DESIGN.md)

## Role

Profile + `RunOptions` → pure **artifacts** (unattend, jobs, servicing stages, DMA contract, manifest). In-process; no DISM; no elevation. Image quality is a **run override**, never a Profile field.

## Interface

```csharp
namespace WinMint.Orchestrator;

public static class BuildPlan
{
    public static Result<Profile, DocumentErrors> TryParseProfile(ReadOnlySpan<byte> utf8Json);
    // Pure: retains authored passwordPath; does not read files.

    public static byte[] SerializeProfile(Profile profile);
    // When PasswordPath is set, emit passwordPath and omit in-memory password.

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null);
    // run null ⇒ ImageQuality.Test; IncludeSmokeStubs false unless harness passes true
}

public static class ProfileFile
{
    public static Result<Profile, DocumentErrors> TryLoad(string profilePath);
    // Host load: read → TryParseProfile → materialize path-backed password.
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
    ServicingStageList Stages,   // ServicingOpcode + params — NOT .ps1 paths
    DmaContract Dma,
    BuildManifest Manifest);
```

Stages: opcodes + params; ImageServicing maps opcode → `servicing/*.ps1`. See [CONTRACTS](CONTRACTS.md).

## Invariants

1. Pure / deterministic: same inputs → same artifacts (stable ordering).
2. No I/O in `Plan` / `TryParseProfile` / `SerializeProfile` — password FS I/O in `ProfileFile.TryLoad`.
3. Failure ⇒ no partial artifacts.
4. Image quality only from `RunOptions` (into `ExportWim` params).
5. DMA enabled ⇒ Ireland latch in unattend **and** settle targets in `DmaContract`.
6. Local+autoLogon ⇒ non-empty password or `PlanFailure` ([SECRETS](SECRETS.md)).
7. Host order: materialize Profile → `Plan` → optional serialize → ImageServicing.Apply.
8. No repo-relative script paths in artifacts.

## Errors

Document errors: schema/JSON/shape; `account.password.sources.conflict` when both password sources set. Plan failures: semantic (`account.password.required`, catalog unknown, …). Exceptions: bugs only.

## Outside this seam

File I/O of artifacts (except shared serialize helpers for jobs/stages/manifest dumps), Source ISO existence, elevated DISM, splash/settle/jobs execution, multiline UI helpers (`IdList.FromMultiline`).

## Profile surface

`winmint.profile/v1` — field names frozen; optional fields may grow without bump. Concrete shape: code + samples. Secrets: [SECRETS](SECRETS.md). Package catalog: `config/packages.json`.
