namespace WinMint.Orchestrator;

/// <summary>
/// Host-only Wizard Station outcomes (#140). Expand to debloat preset + chip/WSL/desktop seed.
/// Outcome names never enter Profile JSON (ADR-005); harness ids stay in <see cref="DebloatPresets"/>.
/// </summary>
public static class StationOutcomes
{
    public const string Minimal = "minimal";
    public const string Comfort = "comfort";
    public const string Power = "power";

    /// <summary>Comfort + denser editor chips (catalog keys); Komorebi is a desktop axis, not a chip key.</summary>
    public static IReadOnlyList<string> PowerToolChipKeys { get; } =
        [.. CuratedDefaults.ToolChipKeys, "neovim", "vscode"];

    public static Result<StationOutcomeExpansion, Failure> TryExpand(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<StationOutcomeExpansion, Failure>(
                new Failure("station.outcome.unknown", "Station outcome name is required."));
        }

        return name.Trim().ToLowerInvariant() switch
        {
            Minimal => Result.Ok<StationOutcomeExpansion, Failure>(
                new StationOutcomeExpansion(
                    DebloatPresets.Empty,
                    [],
                    [],
                    Komorebi: false)),
            Comfort => Result.Ok<StationOutcomeExpansion, Failure>(
                new StationOutcomeExpansion(
                    DebloatPresets.Recommended,
                    CuratedDefaults.ToolChipKeys,
                    CuratedDefaults.WslTokens,
                    Komorebi: false)),
            Power => Result.Ok<StationOutcomeExpansion, Failure>(
                new StationOutcomeExpansion(
                    DebloatPresets.Recommended,
                    PowerToolChipKeys,
                    CuratedDefaults.WslTokens,
                    Komorebi: true)),
            _ => Result.Fail<StationOutcomeExpansion, Failure>(
                new Failure(
                    "station.outcome.unknown",
                    $"Unknown Station outcome '{name.Trim()}'. Use minimal, comfort, or power.")),
        };
    }
}

public sealed record StationOutcomeExpansion(
    string DebloatPreset,
    IReadOnlyList<string> ToolChipKeys,
    IReadOnlyList<string> WslTokens,
    bool Komorebi);
