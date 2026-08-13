using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free Apply glue over an approved composition.</summary>
internal static class WizardBuild
{
    public static string DefaultWorkDirectory => HostDefaults.DefaultWorkDirectory;

    public static string GateBWorkDirectory => HostDefaults.GateBWorkDirectory;

    public static string ResolveWorkDirectory(ImageQualityLane lane, string? workDirectory = null) =>
        HostDefaults.ResolveWorkDirectory(lane, workDirectory);

    public static async Task<WizardBuildResult> TryApplyAsync(
        HostComposition composition,
        IElevatedPlanRunner? runner = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(composition);
        Result<ImageEvidence, Failure> applied =
            await HostCompile.ApplyAsync(composition, runner, cancellationToken).ConfigureAwait(false);
        string work = composition.WorkDirectory;
        if (!applied.IsOk)
        {
            return WizardBuildResult.Fail(
                applied.Error.Code,
                $"{applied.Error.Message} Work directory preserved: {work}");
        }

        ImageEvidence evidence = applied.Value;
        string gateHint = composition.Review.IsGateB
            ? " Gate B wipe media (pre-wipe ISO evidence — not Primary install proven)."
            : " Test lane (not the wipe gate).";
        string ok =
            $"Image OK: {evidence.OutputIsoPath}; Lane={evidence.Lane}; Shell={evidence.ShellStampTargetPath}; Work={work}.{gateHint}";
        return WizardBuildResult.Ok(ok, evidence.OutputIsoPath, work, evidence.Digests);
    }
}

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
