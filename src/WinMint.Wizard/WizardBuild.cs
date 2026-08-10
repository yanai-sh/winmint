using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free build glue — Plan + ImageServicing.Apply (same path as Cli).</summary>
internal static class WizardBuild
{
    public static string DefaultWorkDirectory { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "work");

    public static WizardBuildResult TryApply(
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

        Result<Profile, IReadOnlyList<DocumentError>> parsed = ProfileFile.TryLoad(input.ProfilePath);
        if (!parsed.IsOk)
        {
            string detail = string.Join("; ", parsed.Error.Select(static i => $"{i.Code}: {i.Message}"));
            return WizardBuildResult.Fail("wizard.build.profile.invalid", detail);
        }

        RunOptions runOptions = new()
        {
            ImageQuality = lane,
            SourceIsoPath = input.SourceIsoPath.Trim(),
            OutputIsoPath = string.IsNullOrWhiteSpace(input.OutputIsoPath) ? null : input.OutputIsoPath.Trim(),
        };

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value, runOptions);
        if (!planned.IsOk)
        {
            return WizardBuildResult.Fail(planned.Error.Code, planned.Error.Message);
        }

        string work = string.IsNullOrWhiteSpace(input.WorkDirectory)
            ? DefaultWorkDirectory
            : input.WorkDirectory.Trim();
        Directory.CreateDirectory(work);

        string outIso = string.IsNullOrWhiteSpace(input.OutputIsoPath)
            ? Path.Combine(work, "out.iso")
            : input.OutputIsoPath.Trim();

        ServicingRun run = new(
            SourceIsoPath: input.SourceIsoPath.Trim(),
            WorkDirectory: work,
            OutputIsoPath: outIso,
            WimIndex: input.WimIndex,
            ReuseMedia: input.ReuseMedia);

        IElevatedPlanRunner effective = runner ?? new PwshElevatedPlanRunner();
        Result<ImageEvidence, Failure> applied =
            ImageServicing.Apply(planned.Value, run, effective, cancellationToken);

        if (!applied.IsOk)
        {
            return WizardBuildResult.Fail(
                applied.Error.Code,
                $"{applied.Error.Message} Work directory preserved: {work}");
        }

        string ok =
            $"Image OK: {applied.Value.OutputIsoPath}; Lane={applied.Value.Lane}; Shell={applied.Value.ShellStampTargetPath}";
        return WizardBuildResult.Ok(ok, applied.Value.OutputIsoPath, work);
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
    string? WorkDirectory)
{
    public static WizardBuildResult Ok(string message, string outputIso, string work) =>
        new(true, "ok", message, outputIso, work);

    public static WizardBuildResult Fail(string code, string message) =>
        new(false, code, message, null, null);
}
