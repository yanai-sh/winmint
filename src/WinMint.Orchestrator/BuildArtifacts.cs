namespace WinMint.Orchestrator;

public enum PackagePhase
{
    PerJob,
    WingetImport,
}

public sealed record PlanFailure(string Code, string Message);

public sealed record RunOptions
{
    public ImageQualityLane ImageQuality { get; init; } = ImageQualityLane.Test;
    public string? SourceIsoPath { get; init; }
    public string? OutputIsoPath { get; init; }
    /// <summary>When set, driver catalog entries must match (arm64/amd64/x64).</summary>
    public string? ImageArchitecture { get; init; }
    /// <summary>When set, catalog minimumWindowsBuild is checked at Plan.</summary>
    public int? WindowsBuild { get; init; }

    /// <summary>When true, native ARM64 audit job fails closed on emulated/x64 binaries (SL7/metal).</summary>
    public bool PackageAuditStrict { get; init; }

    /// <summary>When true, package install failures fail the session (harness/metal). Default best-effort.</summary>
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

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,
    ServicingStageList Stages,
    DmaContract Dma,
    BuildManifest Manifest,
    AccountProfile Account,
    IReadOnlyList<string> RemoveProvisionedAppx,
    byte[]? WingetImportJson = null,
    bool PackageStrict = false);

public sealed record UnattendArtifact(string Xml);

public sealed record JobsArtifact(string SchemaVersion, IReadOnlyList<JobDescriptor> Jobs);

public sealed record JobDescriptor(
    string Id,
    string Kind,
    string? PackageId = null,
    bool NeedsReboot = false,
    string? WingetArchitecture = null,
    string? WslInstallKind = null,
    string? WslFromFileRepo = null,
    IReadOnlyList<string>? WslFromFileAssetNames = null,
    bool AuditStrict = false,
    IReadOnlyList<string>? ScoopBuckets = null);

public sealed record ServicingStageList(IReadOnlyList<ServicingStage> Stages);

public sealed record ServicingStage(
    ServicingOpcode Opcode,
    IReadOnlyDictionary<string, string> Parameters);

/// <summary>C#↔PS1 stage parameter keys (stages.json / RunPlan hashtable).</summary>
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
