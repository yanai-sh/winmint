using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;

namespace WinMint.Orchestrator;

public static partial class ImageServicing
{
    /// <summary>
    /// Insert Catalog quality before PatchBootWimApply when Plan omitted it (Apply-time only).
    /// Plan dump stays an empty-param skeleton and never gains this insert.
    /// </summary>
    internal static List<ServicingOpcode> WithQualityUpdateOpcode(IReadOnlyList<ServicingOpcode> stages)
    {
        ArgumentNullException.ThrowIfNull(stages);
        List<ServicingOpcode> opcodes = [.. stages];
        if (!opcodes.Contains(ServicingOpcode.AddQualityUpdates))
        {
            int boot = opcodes.IndexOf(ServicingOpcode.PatchBootWimApply);
            if (boot >= 0)
            {
                opcodes.Insert(boot, ServicingOpcode.AddQualityUpdates);
            }
        }

        return opcodes;
    }

    /// <summary>Frozen plan + workdir paths → bound servicing stages wire (Apply input).</summary>
    internal static Result<BoundServicingStages, Failure> TryBindServicingStages(
        ServicingStageBindContext ctx)
    {
        ArgumentNullException.ThrowIfNull(ctx);

        BuildArtifacts plan = ctx.Plan;
        ServicingRun run = ctx.Run;
        ServicingWorkspace workspace = ctx.Workspace;
        PreparedMediaIdentity identity = ctx.Identity;
        string mediaDir = ctx.MediaDir;
        string mountDir = ctx.MountDir;
        string payloadDir = ctx.PayloadDir;
        string unattendPath = ctx.UnattendPath;
        string wimOut = ctx.WimOut;
        string outputIso = ctx.OutputIso;
        int wimIndex = ctx.WimIndex;

        List<ServicingOpcode> opcodes = WithQualityUpdateOpcode(plan.Stages);
        List<ServicingStage> resolved = new(opcodes.Count);
        List<(ServicingOpcode Opcode, JsonObject Parameters)> wire = new(opcodes.Count);
        void Add<T>(ServicingOpcode opcode, T record, JsonTypeInfo<T> typeInfo)
        {
            JsonObject obj = StageParamJson.From(record, typeInfo);
            wire.Add((opcode, obj));
            resolved.Add(new ServicingStage(opcode, StageParamJson.ToBag(obj)));
        }

        foreach (ServicingOpcode opcode in opcodes)
        {
            switch (opcode)
            {
                case ServicingOpcode.MountInstallWim:
                    Add(
                        opcode,
                        new MountInstallWimParameters(
                            SourceIso: run.SourceIsoPath,
                            MountDir: mountDir,
                            MediaDir: mediaDir,
                            WimIndex: wimIndex,
                            WorkDirectory: workspace.Root,
                            SourceIsoSha256: identity.SourceIsoSha256,
                            SourceIsoLength: identity.SourceIsoLength,
                            CacheSchema: identity.Schema,
                            CacheRoot: PreparedMediaIdentity.Root,
                            ImageName: run.SelectedImage?.Name,
                            Architecture: run.SelectedImage?.Architecture,
                            ImageEdition: run.SelectedImage?.Edition,
                            ImageBuild: run.SelectedImage?.Build),
                        ServicingJsonContext.Default.MountInstallWimParameters);
                    break;
                case ServicingOpcode.StagePayload:
                    Add(
                        opcode,
                        new StagePayloadParameters(payloadDir, mountDir),
                        ServicingJsonContext.Default.StagePayloadParameters);
                    break;
                case ServicingOpcode.StageOobeUnattend:
                    Add(
                        opcode,
                        new StageOobeUnattendParameters(unattendPath, mountDir, mediaDir),
                        ServicingJsonContext.Default.StageOobeUnattendParameters);
                    break;
                case ServicingOpcode.PatchBootWimApply:
                    Add(
                        opcode,
                        new PatchBootWimApplyParameters(mediaDir, mountDir, workspace.Root, workspace.QualityPackages),
                        ServicingJsonContext.Default.PatchBootWimApplyParameters);
                    break;
                case ServicingOpcode.AddQualityUpdates:
                    Add(
                        opcode,
                        new AddQualityUpdatesParameters(
                            mountDir,
                            mediaDir,
                            workspace.Root,
                            HostQualityCacheRoot,
                            workspace.QualityPackages),
                        ServicingJsonContext.Default.AddQualityUpdatesParameters);
                    break;
                case ServicingOpcode.StampOfflineShell:
                    Add(
                        opcode,
                        new StampOfflineShellParameters(ShellStampGuestPath, mountDir),
                        ServicingJsonContext.Default.StampOfflineShellParameters);
                    break;
                case ServicingOpcode.StampOfflinePolicies:
                    Add(
                        opcode,
                        new StampOfflinePoliciesParameters(
                            mountDir,
                            run.WorkDirectory,
                            Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName)),
                        ServicingJsonContext.Default.StampOfflinePoliciesParameters);
                    break;
                case ServicingOpcode.StampOfflineDefaultUser:
                    Add(
                        opcode,
                        new StampOfflineDefaultUserParameters(
                            mountDir,
                            run.WorkDirectory,
                            Path.Combine(payloadDir, ServicingWorkspace.DefaultUserFileName)),
                        ServicingJsonContext.Default.StampOfflineDefaultUserParameters);
                    break;
                case ServicingOpcode.RemoveProvisionedAppx:
                    Add(
                        opcode,
                        new RemoveProvisionedAppxParameters(
                            mountDir,
                            run.WorkDirectory,
                            Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName)),
                        ServicingJsonContext.Default.RemoveProvisionedAppxParameters);
                    break;
                case ServicingOpcode.RemoveCapabilities:
                    Add(
                        opcode,
                        new RemoveCapabilitiesParameters(
                            mountDir,
                            run.WorkDirectory,
                            "capability",
                            Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName)),
                        ServicingJsonContext.Default.RemoveCapabilitiesParameters);
                    break;
                case ServicingOpcode.DisableOptionalFeatures:
                    Add(
                        opcode,
                        new DisableOptionalFeaturesParameters(
                            mountDir,
                            run.WorkDirectory,
                            "feature",
                            Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName)),
                        ServicingJsonContext.Default.DisableOptionalFeaturesParameters);
                    break;
                case ServicingOpcode.InjectDrivers:
                    if (plan.Drivers is null)
                    {
                        return Result.Fail<BoundServicingStages, Failure>(
                            new Failure("servicing.drivers.missing", "InjectDrivers opcode requires DriverInject facts."));
                    }

                    Add(
                        opcode,
                        new InjectDriversParameters(
                            mountDir,
                            run.WorkDirectory,
                            mediaDir,
                            plan.Drivers.DeviceId,
                            plan.Drivers.DetailsUrl,
                            plan.Drivers.ExpectedFileNameRegex,
                            ExportLane.For(plan.Manifest.ImageQuality).Name),
                        ServicingJsonContext.Default.InjectDriversParameters);
                    break;
                case ServicingOpcode.ExportWim:
                    ExportLane exportLane = ExportLane.For(plan.Manifest.ImageQuality);
                    Add(
                        opcode,
                        new ExportWimParameters(
                            mountDir,
                            mediaDir,
                            wimOut,
                            run.WorkDirectory,
                            exportLane.Name,
                            exportLane.Compression,
                            exportLane.Cleanup),
                        ServicingJsonContext.Default.ExportWimParameters);
                    break;
                case ServicingOpcode.BuildIso:
                    Add(
                        opcode,
                        new BuildIsoParameters(outputIso, mediaDir),
                        ServicingJsonContext.Default.BuildIsoParameters);
                    break;
                default:
                    throw new InvalidOperationException($"Unhandled opcode {opcode}");
            }
        }

        return Result.Ok<BoundServicingStages, Failure>(
            new BoundServicingStages([.. resolved], wire));
    }
}

internal sealed record ServicingStageBindContext(
    BuildArtifacts Plan,
    ServicingRun Run,
    ServicingWorkspace Workspace,
    PreparedMediaIdentity Identity,
    string MediaDir,
    string MountDir,
    string PayloadDir,
    string UnattendPath,
    string WimOut,
    string OutputIso,
    int WimIndex);

internal sealed record BoundServicingStages(
    IReadOnlyList<ServicingStage> Stages,
    IReadOnlyList<(ServicingOpcode Opcode, JsonObject Parameters)> Wire);
