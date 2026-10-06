namespace WinMint.Orchestrator;

/// <summary>
/// Host-only Wizard Station outcomes (#140). Deep seed: chip/WSL keys, resolved packages,
/// remove-lists, and desktop axes. Outcome names never enter Profile JSON (ADR-005);
/// harness ids stay in <see cref="DebloatPresets"/>.
/// </summary>
public static class StationOutcomes
{
    public const string Minimal = "minimal";
    public const string Comfort = "comfort";
    public const string Power = "power";

    /// <summary>ADR-015 taskbar surface seed value (Windows taskbar).</summary>
    public const string TaskbarWindows = "windows";

    /// <summary>ADR-015 taskbar surface (YASB + tHide); never seeded by an outcome — user refine only.</summary>
    public const string TaskbarYasb = "yasb";

    private static readonly IReadOnlyList<string> ComfortToolChipKeys = ["cursor", "zen-browser"];
    private static readonly IReadOnlyList<string> ComfortWslTokens = ["FedoraLinux"];
    private static readonly IReadOnlyList<string> PowerToolChipKeys =
        [.. ComfortToolChipKeys, "neovim", "vscode"];

    /// <summary>
    /// Resolve a Station outcome into Wizard seed facts and Profile software slice.
    /// Preset / outcome ids stay inside the implementation.
    /// </summary>
    public static Result<StationSeed, Failure> TrySeed(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<StationSeed, Failure>(
                new Failure("station.outcome.unknown", "Station outcome name is required."));
        }

        string normalized = name.Trim().ToLowerInvariant();
        return normalized switch
        {
            Minimal => Seed(
                toolChipKeys: [],
                wslTokens: [],
                debloatPreset: DebloatPresets.Empty,
                komorebi: false),
            Comfort => Seed(
                ComfortToolChipKeys,
                ComfortWslTokens,
                DebloatPresets.Recommended,
                komorebi: false),
            Power => Seed(
                PowerToolChipKeys,
                ComfortWslTokens,
                DebloatPresets.Recommended,
                komorebi: true),
            _ => Result.Fail<StationSeed, Failure>(
                new Failure(
                    "station.outcome.unknown",
                    $"Unknown Station outcome '{name.Trim()}'. Use minimal, comfort, or power.")),
        };
    }

    private static Result<StationSeed, Failure> Seed(
        IReadOnlyList<string> toolChipKeys,
        IReadOnlyList<string> wslTokens,
        string debloatPreset,
        bool komorebi)
    {
        Result<DebloatExpansion, Failure> debloat = DebloatPresets.TryExpand(debloatPreset);
        if (!debloat.IsOk)
        {
            return Result.Fail<StationSeed, Failure>(debloat.Error);
        }

        Result<ChipAxisResolution, Failure> resolved = ChipAxisResolve.TryResolve(
            toolChipKeys,
            wslTokens,
            TaskbarWindows,
            komorebi);
        if (!resolved.IsOk)
        {
            return Result.Fail<StationSeed, Failure>(resolved.Error);
        }

        return Result.Ok<StationSeed, Failure>(
            new StationSeed(
                ToolChipKeys: toolChipKeys,
                WslTokens: wslTokens,
                Packages: resolved.Value.Packages,
                RemoveProvisionedAppx: debloat.Value.RemoveProvisionedAppx,
                RemoveCapabilities: debloat.Value.RemoveCapabilities,
                DisableOptionalFeatures: debloat.Value.DisableOptionalFeatures,
                TaskbarSurface: TaskbarWindows,
                Komorebi: komorebi,
                SelectionLabels: resolved.Value.SelectionLabels));
    }
}

/// <summary>Resolved Station software seed. Outcome / preset names are not present.</summary>
public sealed record StationSeed(
    IReadOnlyList<string> ToolChipKeys,
    IReadOnlyList<string> WslTokens,
    PackageSelection Packages,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures,
    string TaskbarSurface,
    bool Komorebi,
    IReadOnlyList<string> SelectionLabels);
