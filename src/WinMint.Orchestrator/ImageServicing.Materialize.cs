using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class ImageServicing
{
    private static async Task<Result<PreparedMediaIdentity, Failure>> ResolveMediaIdentity(
        ServicingRun run,
        int wimIndex,
        CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(run.SourceIsoSha256))
        {
            long length = run.SourceIsoLength ?? new FileInfo(run.SourceIsoPath).Length;
            return PreparedMediaIdentity.TryCreate(
                run.SourceIsoSha256,
                length,
                wimIndex,
                PreparedMediaIdentity.CurrentSchema,
                out PreparedMediaIdentity frozen,
                out Failure frozenError)
                ? Result.Ok<PreparedMediaIdentity, Failure>(frozen)
                : Result.Fail<PreparedMediaIdentity, Failure>(frozenError);
        }

        Result<SourceIsoIdentity, Failure> hashed =
            await SourceIsoIdentity.FromFileAsync(run.SourceIsoPath, ct).ConfigureAwait(false);
        if (!hashed.IsOk)
        {
            return Result.Fail<PreparedMediaIdentity, Failure>(hashed.Error);
        }

        return PreparedMediaIdentity.TryCreate(
            hashed.Value.Sha256,
            hashed.Value.Length,
            wimIndex,
            PreparedMediaIdentity.CurrentSchema,
            out PreparedMediaIdentity computed,
            out Failure computedError)
            ? Result.Ok<PreparedMediaIdentity, Failure>(computed)
            : Result.Fail<PreparedMediaIdentity, Failure>(computedError);
    }

    private static async Task<Result<IReadOnlyList<ServicingStage>, Failure>> Materialize(
        BuildArtifacts plan,
        ServicingRun run,
        ServicingWorkspace workspace,
        CancellationToken ct)
    {
        string payloadDir = workspace.Payload;
        if (Directory.Exists(payloadDir))
        {
            Directory.Delete(payloadDir, recursive: true);
        }

        Directory.CreateDirectory(payloadDir);
        string mediaDir = workspace.Media;
        string mountDir = HostMountDir;
        string unattendPath = workspace.Unattend;
        string wimOut = workspace.InstallWim;
        string outputIso = run.OutputIsoPath;
        int wimIndex = run.WimIndex ?? DefaultProWimIndex;
        Result<PreparedMediaIdentity, Failure> identity;
        Stopwatch identityClock = Stopwatch.StartNew();
        try
        {
            identity = await ResolveMediaIdentity(run, wimIndex, ct).ConfigureAwait(false);
        }
        finally
        {
            identityClock.Stop();
        }

        if (!identity.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(identity.Error);
        }

        File.WriteAllText(unattendPath, plan.Unattend.Xml);

        File.WriteAllText(
            Path.Combine(payloadDir, "jobs.json"),
            JobsWire.Write(plan.Jobs.Jobs));

        if (plan.WingetImportJson is { Length: > 0 })
        {
            File.WriteAllBytes(Path.Combine(payloadDir, "winget-import.json"), plan.WingetImportJson);
        }

        string[] removeProvisionedAppx = plan.RemoveProvisionedAppx.ToArray();

        BundleFile bundle = new(
            BundleSchemaVersion,
            ShellStampGuestPath,
            plan.Account.Username,
            plan.Account.Password ?? "",
            plan.Dma.Enabled,
            plan.Dma.Settle is null
                ? null
                : new SettleFile(
                    plan.Dma.Settle.Locale!,
                    plan.Dma.Settle.GeoId!.Value,
                    plan.Dma.Settle.TimeZoneId!,
                    plan.Dma.Settle.LocationServicesEnabled!.Value),
            removeProvisionedAppx,
            plan.Manifest.RequiresNetwork,
            plan.PackageStrict);
        File.WriteAllText(
            Path.Combine(payloadDir, "bundle.json"),
            GuestBundleWire.Write(bundle));

        Result<string, Failure> setupComplete = StageSetupCompleteScript(payloadDir);
        if (!setupComplete.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(setupComplete.Error);
        }

        Result<string, Failure> supervisor = StageSupervisorBinary(payloadDir);
        if (!supervisor.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(supervisor.Error);
        }

        Result<string, Failure> winPeApply = StageWinPeApplyHelper(payloadDir);
        if (!winPeApply.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(winPeApply.Error);
        }

        Result<string, Failure> shellSkel = StageShellSkel(payloadDir);
        if (!shellSkel.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(shellSkel.Error);
        }

        File.WriteAllBytes(
            Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName),
            JsonSerializer.SerializeToUtf8Bytes(
                plan.OfflinePolicies.ToArray(),
                ServicingJsonContext.Default.OfflinePolicyRowArray));

        if (plan.RemoveProvisionedAppx.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.RemoveProvisionedAppx.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.RemoveCapabilities.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.RemoveCapabilities.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.DisableOptionalFeatures.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.DisableOptionalFeatures.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        List<ServicingStage> resolved = new(plan.Stages.Count);
        List<(ServicingOpcode Opcode, JsonObject Parameters)> wire = new(plan.Stages.Count);
        void Add<T>(ServicingOpcode opcode, T record, JsonTypeInfo<T> typeInfo)
        {
            JsonObject obj = StageParamJson.From(record, typeInfo);
            wire.Add((opcode, obj));
            resolved.Add(new ServicingStage(opcode, StageParamJson.ToBag(obj)));
        }

        foreach (ServicingOpcode opcode in plan.Stages)
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
                            SourceIsoSha256: identity.Value.SourceIsoSha256,
                            SourceIsoLength: identity.Value.SourceIsoLength,
                            CacheSchema: identity.Value.Schema,
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
                        new PatchBootWimApplyParameters(mediaDir, mountDir, workspace.Root),
                        ServicingJsonContext.Default.PatchBootWimApplyParameters);
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
                        return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(
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
                            plan.Drivers.ExpectedFileNameRegex),
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

        File.WriteAllText(workspace.Stages, SerializeServicingStagesFile(wire));
        workspace.WriteManifest();
        WriteExpectedEvidence(workspace, plan, resolved);

        return Result.Ok<IReadOnlyList<ServicingStage>, Failure>(resolved.ToArray());
    }

    private static Result<string, Failure> StageSetupCompleteScript(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "SetupComplete.cmd");
        string? source = FindSetupCompleteScript();
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.setupComplete.missing",
                    "payload/scripts/SetupComplete.cmd not found."));
        }

        File.Copy(source, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageSupervisorBinary(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "Supervisor.exe");
        string? published = FindPublishedSupervisor();
        if (published is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.supervisor.missing",
                    "Published Supervisor not found. Run: just publish-provisioning"));
        }

        File.Copy(published, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageWinPeApplyHelper(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "WinMintApply.exe");
        string? published = FindPublishedWinPeApply();
        if (published is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.winPeApply.missing",
                    "Published WinMintApply not found. Run: just publish-provisioning"));
        }

        File.Copy(published, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageShellSkel(string payloadDir)
    {
        string? source = FindShellSkelDirectory();
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.shellSkel.missing",
                    "payload/shell-skel not found."));
        }

        string dest = Path.Combine(payloadDir, "shell-skel");
        CopyDirectory(source, dest);
        return Result.Ok<string, Failure>(dest);
    }

    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (string file in Directory.EnumerateFiles(sourceDir))
        {
            File.Copy(file, Path.Combine(destDir, Path.GetFileName(file)), overwrite: true);
        }

        foreach (string dir in Directory.EnumerateDirectories(sourceDir))
        {
            CopyDirectory(dir, Path.Combine(destDir, Path.GetFileName(dir)));
        }
    }

    private static string? FindShellSkelDirectory() =>
        ToolkitRoot.TryFind("payload", "shell-skel");

    private static string? FindSetupCompleteScript() =>
        ToolkitRoot.TryFind("payload", "scripts", "SetupComplete.cmd");

    private static string? FindPublishedSupervisor()
    {
        string sideBySide = Path.Combine(AppContext.BaseDirectory, "WinMint.Provisioning.exe");
        return ToolkitRoot.TryFind("artifacts", "provisioning", "WinMint.Provisioning.exe")
            ?? (File.Exists(sideBySide) ? sideBySide : null);
    }

    private static string? FindPublishedWinPeApply()
    {
        string sideBySide = Path.Combine(AppContext.BaseDirectory, "WinMintApply.exe");
        return ToolkitRoot.TryFind("artifacts", "winpe-apply", "WinMintApply.exe")
            ?? (File.Exists(sideBySide) ? sideBySide : null);
    }
}
