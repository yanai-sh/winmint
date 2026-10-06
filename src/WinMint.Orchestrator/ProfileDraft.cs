using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>
/// Shared Profile assembly from Station outcome remove-lists + account + DMA + packages (#151).
/// Callers own bootstrap emit and Wizard shipping pins (ADR-016).
/// </summary>
public static class ProfileDraft
{
    public static Result<Profile, Failure> TryBuild(
        string stationOutcome,
        AccountProfile account,
        DmaProfile dma,
        PackageSelection packages,
        string? advancedWinget = null,
        string? advancedScoop = null,
        string? advancedWsl = null)
    {
        ArgumentNullException.ThrowIfNull(account);
        ArgumentNullException.ThrowIfNull(dma);
        ArgumentNullException.ThrowIfNull(packages);

        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(stationOutcome);
        if (!seed.IsOk)
        {
            return Result.Fail<Profile, Failure>(seed.Error);
        }

        StationSeed software = seed.Value;
        return Result.Ok<Profile, Failure>(
            new Profile(
                account,
                dma,
                DebloatMode.Online,
                software.RemoveProvisionedAppx,
                MergeChipAndAdvanced(packages.WingetInstallIds, advancedWinget),
                [],
                MergeChipAndAdvanced(packages.ScoopInstallIds, advancedScoop),
                [],
                MergeChipAndAdvanced(packages.WslProfileTokens, advancedWsl),
                [],
                software.RemoveCapabilities,
                software.DisableOptionalFeatures));
    }

    public static Result<DmaProfile, Failure> TryParseDma(
        bool enabled,
        string locale,
        string geoId,
        string timeZoneId,
        bool locationServices)
    {
        if (!int.TryParse(geoId.Trim(), out int parsedGeoId))
        {
            return Result.Fail<DmaProfile, Failure>(
                new Failure("dma.settle.geoId", "must be an integer."));
        }

        return Result.Ok<DmaProfile, Failure>(
            new DmaProfile(
                enabled,
                new DmaSettleTarget(
                    locale.Trim(),
                    parsedGeoId,
                    timeZoneId.Trim(),
                    locationServices)));
    }

    private static IReadOnlyList<string> MergeChipAndAdvanced(
        IEnumerable<string> selectedChipIds,
        string? advancedMultiline) =>
        IdList.UnionOrdered(selectedChipIds, IdList.FromMultiline(advancedMultiline));
}
