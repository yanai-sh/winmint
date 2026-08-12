using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free build glue — thin HostCompile adapter (same path as Cli).</summary>
internal static class WizardBuild
{
    public static string DefaultWorkDirectory => HostDefaults.DefaultWorkDirectory;

    public static string GateBWorkDirectory => HostDefaults.GateBWorkDirectory;

    public static string ResolveWorkDirectory(ImageQualityLane lane, string? workDirectory = null) =>
        HostDefaults.ResolveWorkDirectory(lane, workDirectory);

    public static async Task<WizardBuildResult> TryApplyAsync(
        WizardBuildInput input,
        IElevatedPlanRunner? runner = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(input.ProfilePath) || !File.Exists(input.ProfilePath))
        {
            return WizardBuildResult.Fail(
                "wizard.build.profile.missing",
                "Save a Profile JSON before building.");
        }

        if (string.IsNullOrWhiteSpace(input.SourceIsoPath) || !File.Exists(input.SourceIsoPath))
        {
            return WizardBuildResult.Fail(
                "wizard.build.sourceIso.missing",
                $"Source ISO not found: {input.SourceIsoPath}");
        }

        if (!WizardSession.TryParseLane(input.ImageQualityText, out ImageQualityLane lane, out string? laneError))
        {
            return WizardBuildResult.Fail("wizard.build.imageQuality", laneError!);
        }

        HostCompileRequest request = new(
            ProfilePath: input.ProfilePath,
            SourceIsoPath: input.SourceIsoPath.Trim(),
            ImageQuality: lane,
            WorkDirectory: input.WorkDirectory,
            OutputIsoPath: string.IsNullOrWhiteSpace(input.OutputIsoPath) ? null : input.OutputIsoPath.Trim(),
            WimIndex: input.WimIndex,
            ReuseMedia: input.ReuseMedia);

        Result<ImageEvidence, Failure> applied =
            await HostCompile.ApplyAsync(request, runner, cancellationToken).ConfigureAwait(false);

        string work = HostDefaults.ResolveWorkDirectory(lane, input.WorkDirectory);
        if (!applied.IsOk)
        {
            string code = applied.Error.Code switch
            {
                "hostCompile.profile.invalid" => "wizard.build.profile.invalid",
                "hostCompile.profile.missing" => "wizard.build.profile.missing",
                "hostCompile.sourceIso.missing" => "wizard.build.sourceIso.missing",
                _ => applied.Error.Code,
            };
            return WizardBuildResult.Fail(
                code,
                $"{applied.Error.Message} Work directory preserved: {work}");
        }

        bool packageStrict = HostDefaults.PackageStrictFor(lane);
        string gateHint = packageStrict
            ? " Gate B wipe media (pre-wipe ISO evidence — not Primary install proven)."
            : " Test lane (not the wipe gate).";
        string ok =
            $"Image OK: {applied.Value.OutputIsoPath}; Lane={applied.Value.Lane}; Shell={applied.Value.ShellStampTargetPath}; Work={work}.{gateHint}";
        return WizardBuildResult.Ok(ok, applied.Value.OutputIsoPath, work, applied.Value.Digests);
    }
}

internal sealed record WizardBuildInput(
    string ProfilePath,
    string SourceIsoPath,
    string ImageQualityText = "Test",
    string? WorkDirectory = null,
    string? OutputIsoPath = null,
    int? WimIndex = null,
    bool ReuseMedia = false);

internal sealed record WizardBuildResult(
    bool Succeeded,
    string Code,
    string Message,
    string? OutputIsoPath,
    string? WorkDirectory,
    IReadOnlyDictionary<string, string>? Digests)
{
    public static WizardBuildResult Ok(
        string message,
        string outputIso,
        string work,
        IReadOnlyDictionary<string, string> digests) =>
        new(true, "ok", message, outputIso, work, digests);

    public static WizardBuildResult Fail(string code, string message) =>
        new(false, code, message, null, null, null);
}
