namespace WinMint.Orchestrator;

/// <summary>
/// Deep resolve: curated chip keys, WSL tokens, and ADR-015 desktop axes → packages + selection labels.
/// </summary>
public static class ChipAxisResolve
{
    public static Result<ChipAxisResolution, Failure> TryResolve(
        IReadOnlyList<string> toolChipKeys,
        IReadOnlyList<string> wslTokens,
        string taskbarSurface,
        bool komorebi)
    {
        IEnumerable<string> resolveKeys = toolChipKeys;
        if (string.Equals(taskbarSurface, StationOutcomes.TaskbarYasb, StringComparison.Ordinal))
        {
            resolveKeys = resolveKeys.Concat([PackageChips.Yasb]);
        }

        if (komorebi)
        {
            resolveKeys = resolveKeys.Concat([PackageChips.Komorebi, PackageChips.Whkd]);
        }

        resolveKeys = resolveKeys.Where(CuratedPackageChips.IsPackageTool);

        Result<PackageSelection, Failure> tools = PackageCatalog.Default.ResolveToolKeys(resolveKeys);
        if (!tools.IsOk)
        {
            return Result.Fail<ChipAxisResolution, Failure>(tools.Error);
        }

        Result<IReadOnlyList<string>, Failure> wsl = PackageCatalog.Default.ResolveWslTokens(wslTokens);
        if (!wsl.IsOk)
        {
            return Result.Fail<ChipAxisResolution, Failure>(wsl.Error);
        }

        PackageSelection packages = new(
            tools.Value.WingetInstallIds,
            tools.Value.ScoopInstallIds,
            wsl.Value);

        IReadOnlyList<string> labels = BuildSelectionLabels(
            taskbarSurface,
            komorebi,
            toolChipKeys,
            wslTokens);

        return Result.Ok<ChipAxisResolution, Failure>(
            new ChipAxisResolution(packages, labels));
    }

    private static List<string> BuildSelectionLabels(
        string taskbarSurface,
        bool komorebi,
        IReadOnlyList<string> toolChipKeys,
        IReadOnlyList<string> wslTokens)
    {
        List<string> labels =
        [
            string.Equals(taskbarSurface, StationOutcomes.TaskbarYasb, StringComparison.Ordinal)
                ? "YASB + tHide"
                : "Windows taskbar",
        ];
        if (komorebi)
        {
            labels.Add("Komorebi");
        }

        Dictionary<string, string> chipLabels = CuratedPackageChips.Browsers
            .Concat(CuratedPackageChips.Editors)
            .Concat(CuratedPackageChips.Wsl)
            .ToDictionary(c => c.Key, c => c.Label, StringComparer.OrdinalIgnoreCase);

        foreach (string key in toolChipKeys.Concat(wslTokens))
        {
            if (chipLabels.TryGetValue(key, out string? label))
            {
                labels.Add(label);
            }
        }

        return labels;
    }
}

public sealed record ChipAxisResolution(
    PackageSelection Packages,
    IReadOnlyList<string> SelectionLabels);
