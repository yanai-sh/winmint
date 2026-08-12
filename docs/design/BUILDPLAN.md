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
    public static Result<Profile, IReadOnlyList<DocumentError>> TryParseProfile(ReadOnlySpan<byte> utf8Json);
    // Pure: retains authored passwordPath; does not read files.

    public static byte[] SerializeProfile(Profile profile);
    // When PasswordPath is set, emit passwordPath and omit in-memory password.

    public static Result<BuildArtifacts, Failure> Plan(Profile profile, RunOptions? run = null);
    // run null ⇒ ImageQuality.Test; IncludeSmokeStubs false unless harness passes true
}

public static class ProfileFile
{
    public static Result<Profile, IReadOnlyList<DocumentError>> TryLoad(string profilePath);
    // Host load: read → TryParseProfile → materialize path-backed password.
}

public sealed record RunOptions
{
    public ImageQualityLane ImageQuality { get; init; } = ImageQualityLane.Test;
    public string? SourceIsoPath { get; init; }
    public string? OutputIsoPath { get; init; }
    // + ImageArchitecture, WindowsBuild, PackageAuditStrict, PackageStrict (caller-owned; default false),
    //   IncludeSmokeStubs, PackageCatalog override — see BuildArtifacts.cs
}

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,           // IReadOnlyList<ProvisionJob> — WinMint.Contracts
    ServicingStageList Stages,   // ServicingOpcode + params — NOT .ps1 paths
    DmaContract Dma,
    BuildManifest Manifest,
    AccountProfile Account,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<EffectivePackageFact> EffectivePackages,
    byte[]? WingetImportJson = null,
    bool PackageStrict = false);
```

Stages: opcodes + params; ImageServicing maps opcode → `servicing/*.ps1`. See [CONTRACTS](CONTRACTS.md).

Package planning is one internal operation over Profile, PackageCatalog, effective image architecture, and audit strictness. It returns the complete package-job slice, deterministic winget import bytes, and typed `EffectivePackageFact` rows (source, resolved install id, ProductPosture/Profile origin, reboot requirement). Wizard Review consumes those facts from the same `Plan` call; it does not re-plan packages. Execution consumes `Jobs` and `WingetImportJson`. `PackageStrict` is stamped into the guest bundle but is not implied by Release lane — callers pass it explicitly (Wizard Release Build and Gate B do; Cli defaults false).

## Invariants

1. Pure / deterministic: same inputs → same artifacts (stable ordering).
2. No I/O in `Plan` / `TryParseProfile` / `SerializeProfile` — password FS I/O in `ProfileFile.TryLoad`.
3. Failure ⇒ no partial artifacts.
4. Image quality only from `RunOptions` (into `ExportWim` params).
5. DMA enabled ⇒ Ireland sticky setup region (`DeviceRegion` 68 + `.DEFAULT` Geo) in unattend **and** settle targets in `DmaContract`.
6. Local+autoLogon ⇒ non-empty password or `Failure` ([SECRETS](SECRETS.md)).
7. Host order: materialize Profile → `Plan` → optional serialize → ImageServicing.Apply.
8. No repo-relative script paths in artifacts.

## Errors

Document errors: schema/JSON/shape; `account.password.sources.conflict` when both password sources set. Plan failures: semantic (`account.password.required`, catalog unknown, …). Exceptions: bugs only.

## Outside this seam

File I/O of artifacts (except shared serialize helpers for jobs/stages/manifest dumps), Source ISO existence, elevated DISM, splash/settle/jobs execution, multiline UI helpers (`IdList.FromMultiline`).

## Profile surface

`winmint.profile/v1` — field names frozen; optional fields may grow without bump. Concrete shape: code + samples. Secrets: [SECRETS](SECRETS.md). Package catalog: `config/packages.json`.
