using System.Diagnostics;
using System.Text.Json;

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

        string[] removeProvisionedAppx = [.. plan.RemoveProvisionedAppx];

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

        Result<string, Failure> bloom = StageBloomWallpaper(payloadDir);
        if (!bloom.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(bloom.Error);
        }

        Result<string, Failure> fonts = StageCascadiaFonts(payloadDir);
        if (!fonts.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(fonts.Error);
        }

        Result<string, Failure> desktop = StageDesktopAssets(payloadDir);
        if (!desktop.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(desktop.Error);
        }

        File.WriteAllBytes(
            Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName),
            JsonSerializer.SerializeToUtf8Bytes(
                [.. plan.OfflinePolicies],
                ServicingJsonContext.Default.OfflinePolicyRowArray));

        File.WriteAllBytes(
            Path.Combine(payloadDir, ServicingWorkspace.DefaultUserFileName),
            JsonSerializer.SerializeToUtf8Bytes(
                [.. plan.OfflineDefaultUser ?? []],
                ServicingJsonContext.Default.OfflinePolicyRowArray));

        File.WriteAllText(
            Path.Combine(payloadDir, ServicingWorkspace.LayoutModificationFileName),
            GuestChrome.TaskbarLayoutBaselineXml);

        if (plan.RemoveProvisionedAppx.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    [.. plan.RemoveProvisionedAppx],
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.RemoveCapabilities.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    [.. plan.RemoveCapabilities],
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.DisableOptionalFeatures.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    [.. plan.DisableOptionalFeatures],
                    ServicingJsonContext.Default.StringArray));
        }

        Result<BoundServicingStages, Failure> bound = TryBindServicingStages(
            new ServicingStageBindContext(
                Plan: plan,
                Run: run,
                Workspace: workspace,
                Identity: identity.Value,
                MediaDir: mediaDir,
                MountDir: mountDir,
                PayloadDir: payloadDir,
                UnattendPath: unattendPath,
                WimOut: wimOut,
                OutputIso: outputIso,
                WimIndex: wimIndex));
        if (!bound.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(bound.Error);
        }

        File.WriteAllText(workspace.Stages, SerializeServicingStagesFile(bound.Value.Wire));
        workspace.WriteManifest();
        WriteExpectedEvidence(workspace, plan, bound.Value.Stages);

        return Result.Ok<IReadOnlyList<ServicingStage>, Failure>(bound.Value.Stages);
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

    private static Result<string, Failure> StageBloomWallpaper(string payloadDir)
    {
        string? source = ToolkitRoot.TryFind("payload", "media", "wallpaper", "bloom.jpg");
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure("servicing.bloom.missing", "payload/media/wallpaper/bloom.jpg not found."));
        }

        string dest = Path.Combine(payloadDir, "bloom.jpg");
        File.Copy(source, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageCascadiaFonts(string payloadDir)
    {
        string destDir = Path.Combine(payloadDir, "fonts");
        Directory.CreateDirectory(destDir);
        string[] names = ["CascadiaCodeNF.ttf", "CascadiaMonoNF.ttf"];
        foreach (string name in names)
        {
            string? source = ToolkitRoot.TryFind("payload", "fonts", name);
            if (source is null)
            {
                return Result.Fail<string, Failure>(
                    new Failure("servicing.fonts.missing", $"payload/fonts/{name} not found."));
            }

            File.Copy(source, Path.Combine(destDir, name), overwrite: true);
        }

        return Result.Ok<string, Failure>(destDir);
    }

    private static Result<string, Failure> StageDesktopAssets(string payloadDir)
    {
        string? source = ToolkitRoot.TryFind("payload", "desktop");
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure("servicing.desktop.missing", "payload/desktop not found."));
        }

        string dest = Path.Combine(payloadDir, "desktop");
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
