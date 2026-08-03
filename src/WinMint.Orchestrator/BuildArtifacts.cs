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

public sealed record JobDescriptor(string Id, string Kind);

public sealed record PayloadManifest(IReadOnlyList<string> Entries);

public sealed record ServicingStageList(IReadOnlyList<ServicingStage> Stages);

public sealed record ServicingStage(
    ServicingOpcode Opcode,
    IReadOnlyDictionary<string, string> Parameters);

public enum ServicingOpcode
{
    MountInstallWim,
    StagePayload,
    InjectUnattend,
    StampOfflineShell,
    ExportWim,
    BuildIso,
}

public sealed record DmaContract(bool Enabled, DmaSettleTarget? Settle);

public sealed record BuildManifest(ImageQualityLane ImageQuality);
