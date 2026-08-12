using System.Collections.Frozen;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public enum EffectivePackageSource
{
    Winget,
    Store,
    Scoop,
    Wsl,
}

public enum EffectivePackageOrigin
{
    ProductPosture,
    Profile,
}

public readonly record struct Failure(string Code, string Message);

public sealed record RunOptions
{
    public ImageQualityLane ImageQuality { get; init; } = ImageQualityLane.Test;
    public string? SourceIsoPath { get; init; }
    public string? OutputIsoPath { get; init; }
    /// <summary>When set, driver catalog entries must match (arm64/amd64/x64).</summary>
    public string? ImageArchitecture { get; init; }
    /// <summary>When set, catalog minimumWindowsBuild is checked at Plan.</summary>
    public int? WindowsBuild { get; init; }

    /// <summary>When true, native ARM64 audit job fails closed on emulated/x64 binaries (SL7/Primary).</summary>
    public bool PackageAuditStrict { get; init; }

    /// <summary>When true, package install failures fail the session (harness/Primary). Caller-owned; default best-effort.</summary>
    public bool PackageStrict { get; init; }

    /// <summary>When true, Plan emits smoke.stub.* jobs (Smoke/acceptance harness). Default false.</summary>
    public bool IncludeSmokeStubs { get; init; }

    /// <summary>Override embedded package catalog (tests); null uses <see cref="PackageCatalog.Default"/>.</summary>
    public PackageCatalog? PackageCatalog { get; init; }
}

public enum ImageQualityLane
{
    Test,
    Release,
}

public sealed record ExportLane(string Name, string Compression, string Cleanup)
{
    public static ExportLane For(ImageQualityLane lane) =>
        lane switch
        {
            ImageQualityLane.Test => new("Test", "fast", "skip"),
            ImageQualityLane.Release => new("Release", "max", "full"),
            _ => throw new ArgumentOutOfRangeException(nameof(lane), lane, "Unsupported image-quality lane."),
        };
}

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,
    ServicingStageList Stages,
    DmaContract Dma,
    BuildManifest Manifest,
    AccountProfile Account,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<EffectivePackageFact> EffectivePackages,
    byte[]? WingetImportJson = null,
    bool PackageStrict = false);

public sealed record EffectivePackageFact(
    EffectivePackageSource Source,
    string ResolvedInstallId,
    EffectivePackageOrigin Origin,
    bool NeedsReboot);

public sealed record UnattendArtifact(string Xml);

public sealed record JobsArtifact(string SchemaVersion, IReadOnlyList<ProvisionJob> Jobs);

public sealed record ServicingStageList(IReadOnlyList<ServicingStage> Stages);

public sealed record ServicingStage(
    ServicingOpcode Opcode,
    IReadOnlyDictionary<string, string> Parameters)
{
    /// <summary>Freeze a mutable parameter bag so later callers cannot mutate published stages.</summary>
    public ServicingStage(ServicingOpcode opcode, Dictionary<string, string> parameters)
        : this(
            opcode,
            (IReadOnlyDictionary<string, string>)parameters.ToFrozenDictionary(StringComparer.Ordinal))
    {
    }
}

/// <summary>C#↔PS1 stage parameter keys (stages.json / Invoke-ServicingPlan hashtable).</summary>
public static class StageParams
{
    public const string SourceIso = "sourceIso";
    public const string MountDir = "mountDir";
    public const string MediaDir = "mediaDir";
    public const string WimIndex = "wimIndex";
    public const string ReuseMedia = "reuseMedia";
    public const string PayloadDir = "payloadDir";
    public const string UnattendPath = "unattendPath";
    public const string ShellTarget = "shellTarget";
    public const string WimOut = "wimOut";
    public const string OutputIso = "outputIso";
    public const string Lane = "lane";
    public const string Compression = "compression";
    public const string Cleanup = "cleanup";
    public const string PackageFamilyNames = "packageFamilyNames";
    public const string CapabilityNames = "capabilityNames";
    public const string FeatureNames = "featureNames";
    public const string WorkDirectory = "workDirectory";
    public const string Kind = "kind";
    public const string PolicySpecs = "policySpecs";
    public const string DeviceId = "deviceId";
    public const string DetailsUrl = "detailsUrl";
    public const string ExpectedFileNameRegex = "expectedFileNameRegex";
    public const string MinimumWindowsBuild = "minimumWindowsBuild";
    public const string Architecture = "architecture";
}

public enum ServicingOpcode
{
    MountInstallWim,
    StagePayload,
    StageOobeUnattend,
    PatchBootWimApply,
    StampOfflineShell,
    StampOfflinePolicies,
    RemoveProvisionedAppx,
    RemoveCapabilities,
    DisableOptionalFeatures,
    InjectDrivers,
    ExportWim,
    BuildIso,
}

public sealed record DmaContract(bool Enabled, DmaSettleTarget? Settle);

public sealed record BuildManifest(ImageQualityLane ImageQuality, bool RequiresNetwork);
