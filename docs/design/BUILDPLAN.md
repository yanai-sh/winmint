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

    public static string SerializePlanStagesFile(
        IReadOnlyList<ServicingOpcode> stages,
        DriverInject? drivers = null,
        ImageQualityLane lane = ImageQualityLane.Test);
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
    // + ImageArchitecture, WindowsBuild, PackageAuditStrict, resolved PackageStrict,
    //   IncludeSmokeStubs, PackageCatalog override — see BuildArtifacts.cs
}

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,           // IReadOnlyList<ProvisionJob> — WinMint.Contracts
    IReadOnlyList<ServicingOpcode> Stages,
    DmaContract Dma,
    BuildManifest Manifest,
    AccountProfile Account,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<EffectivePackageFact> EffectivePackages,
    IReadOnlyList<OfflinePolicyRow> OfflinePolicies,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures,
    byte[]? WingetImportJson = null,
    bool PackageStrict = false,
    bool BraveSelected = false,
    DriverInject? Drivers = null);
```

`BuildArtifacts` is BuildPlan's internal result vocabulary. Front ends enter through HostCompile: document-only `validate` / `plan` receive `HostPlan` via `PlanDocument(HostComposeOptions)`, while build flows receive an immutable `HostComposition` with a secret-free `HostReview`. HostCompile deep-snapshots the approved artifacts and keeps them private through Apply. Honesty and Gate B (`HostReview.IsGateB` = Release ∧ package-strict) are HostReview projections.

Stages: opcode list plus optional `DriverInject`. ImageServicing maps opcode → `servicing/*.ps1`, serializes typed Kernel records into `winmint.servicing.stages/v1`, and writes policy/AppX/component lists as JSON under `payload/`. Cli diagnostic dumps use `winmint.plan.stages/v1` (InjectDrivers + ExportWim diagnostic keys only); only ImageServicing materialization emits `winmint.servicing.stages/v1`. Jobs JSON is owned by `JobsWire.Write` / `TryParse` in Contracts. Guest `bundle.json` is owned by `GuestBundleWire.Write` / `TryParse`. See [CONTRACTS](CONTRACTS.md).

Package planning is one internal operation over Profile, PackageCatalog, effective image architecture, and audit strictness. It returns the complete package-job slice, deterministic winget import bytes, and typed `EffectivePackageFact` rows (source, resolved install id, ProductPosture/Profile origin, reboot requirement). Wizard Review consumes those facts from the same `Plan` call; it does not re-plan packages. Execution consumes `Jobs` and `WingetImportJson`. HostCompile resolves `PackageStrictOverride` once: Test defaults false, Release defaults true, and explicit Force/Suppress overrides the lane. The resolved bool is stamped into the guest bundle.

## Invariants

1. Pure / deterministic: same inputs → same artifacts (stable ordering).
2. No I/O in `Plan` / `TryParseProfile` / `SerializeProfile` — password FS I/O in `ProfileFile.TryLoad`.
3. Failure ⇒ no partial artifacts.
4. Image quality only from `RunOptions`. ExportWim lane is derived via `ExportLane.For(Manifest.ImageQuality)` at dump/materialize — not stored as a plan bag.
5. DMA enabled ⇒ Ireland sticky setup region (`DmaInterop` DeviceRegion + `.DEFAULT` Geo hive paths) in unattend **and** settle targets in `DmaContract`. Enabled stays on the outer DMA object, not nested settle.
6. Local+autoLogon ⇒ non-empty password or `Failure` ([SECRETS](SECRETS.md)).
7. Host order: materialize Profile → HostCompile composition (serialize + one `Plan`) → immutable approval → ImageServicing.Apply; Apply never reloads or replans.
8. No repo-relative script paths in artifacts.

## Errors

Document errors: schema/JSON/shape; `account.password.sources.conflict` when both password sources set. Plan failures: semantic (`account.password.required`, catalog unknown, …). Exceptions: bugs only.

## Outside this seam

File I/O of artifacts (except stage/manifest dump serializers), Source ISO existence, elevated DISM, splash/settle/jobs execution, multiline UI helpers (`IdList.FromMultiline`). Jobs wire serialization is not a BuildPlan responsibility; both Cli and ImageServicing call `JobsWire`.

## Profile surface

`winmint.profile/v1` — field names frozen; optional fields may grow without bump. Concrete shape: code + samples. Secrets: [SECRETS](SECRETS.md). Package catalog: `config/packages.json`.
