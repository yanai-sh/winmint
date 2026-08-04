namespace WinMint.Orchestrator;

public sealed record PlanFailure(string Code, string Message);

public sealed record RunOptions
{
    public ImageQualityLane ImageQuality { get; init; } = ImageQualityLane.Test;
    public string? SourceIsoPath { get; init; }
    public string? OutputIsoPath { get; init; }
}

public enum ImageQualityLane
{
    Test,
    Release,
}

public sealed record BuildArtifacts(
    UnattendArtifact Unattend,
    JobsArtifact Jobs,
    PayloadManifest Payload,
    ServicingStageList Stages,
    DmaContract Dma,
    BuildManifest Manifest,
    AccountProfile Account);

public sealed record UnattendArtifact(string Xml);

public sealed record JobsArtifact(string SchemaVersion, IReadOnlyList<JobDescriptor> Jobs);

public sealed record JobDescriptor(
    string Id,
    string Kind,
    string? PackageId = null,
    bool NeedsReboot = false);

public sealed record PayloadManifest(IReadOnlyList<string> Entries);

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
    public const string WorkDirectory = "workDirectory";
}

public enum ServicingOpcode
{
    MountInstallWim,
    StagePayload,
    InjectUnattend,
    StampOfflineShell,
    RemoveProvisionedAppx,
    ExportWim,
    BuildIso,
}

public sealed record DmaContract(bool Enabled, DmaSettleTarget? Settle);

public sealed record BuildManifest(ImageQualityLane ImageQuality);
