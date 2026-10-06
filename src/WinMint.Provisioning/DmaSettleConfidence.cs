using System.Security;

using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// DMA settle hard/soft/latch outcomes. Final snapshot gates hard fields;
/// intermediate probe and re-apply failures fail-open inside this module.
/// </summary>
internal static class DmaSettleConfidence
{
    internal static bool HardFieldsMatch(RegionState actual, DmaSettleTarget target) =>
        string.Equals(actual.Locale, target.Locale, StringComparison.OrdinalIgnoreCase)
        && actual.GeoId == target.GeoId
        && string.Equals(actual.TimeZoneId, target.TimeZoneId, StringComparison.OrdinalIgnoreCase);

    internal static SessionStatus? TargetIncompleteStatus(DmaSettleTarget dma)
    {
        if (string.IsNullOrWhiteSpace(dma.Locale)
            || dma.GeoId is null
            || string.IsNullOrWhiteSpace(dma.TimeZoneId)
            || dma.LocationServicesEnabled is null)
        {
            return new SessionStatus(
                "settle.targetIncomplete",
                "DMA settle requires locale, geoId, timeZoneId, and locationServicesEnabled.");
        }

        return null;
    }

    /// <summary>
    /// One poll probe: read (fail-open), optional re-apply on hard drift (fail-open).
    /// Returns whether hard fields already match the target.
    /// </summary>
    internal static bool TryPollProbe(IRegionSnapshot region, DmaSettleTarget target, out RegionState? snapshot)
    {
        snapshot = null;
        try
        {
            RegionState snap = region.Read();
            snapshot = snap;
            if (HardFieldsMatch(snap, target))
            {
                return true;
            }

            TryReapply(region, target);
            return false;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // ponytail: intermediate DMA probe fail-open — final snapshot after loop is authoritative
            _ = ex;
            return false;
        }
    }

    internal static SessionStatus HardMismatchStatus(RegionState final) =>
        new(
            "settle.hardMismatch",
            $"Final snapshot hard fields mismatch (locale={final.Locale}, geoId={final.GeoId}, tz={final.TimeZoneId}).");

    internal static SessionStatus? LocationWarnStatus(RegionState final, DmaSettleTarget target)
    {
        if (target.LocationServicesEnabled is bool expectedLocation
            && final.LocationServicesEnabled != expectedLocation)
        {
            return new SessionStatus(
                "settle.locationWarn",
                $"Location-services posture is {final.LocationServicesEnabled}; expected {expectedLocation}.");
        }

        return null;
    }

    internal static SessionStatus DeviceRegionStatus(DmaSetupRegionLatch latch) =>
        latch.Kind switch
        {
            DmaSetupRegionLatchKind.Ok when latch.EnsureResult == DmaSetupRegionEnsureResult.Repaired =>
                new("settle.deviceRegionRepaired", "DeviceRegion repaired to Ireland (68)."),
            DmaSetupRegionLatchKind.Ok =>
                new("settle.deviceRegionOk", "DeviceRegion already Ireland (68)."),
            DmaSetupRegionLatchKind.MissingPort =>
                new("settle.deviceRegionFailed", "DmaSetup port required when DMA enabled."),
            _ => new("settle.deviceRegionFailed", latch.Message ?? "DeviceRegion latch failed."),
        };

    internal static bool DeviceRegionHardFailed(DmaSetupRegionLatch latch) =>
        latch.Kind is not DmaSetupRegionLatchKind.Ok;

    /// <summary>
    /// Sticky Ireland DeviceRegion latch (ADR-003). Machine setup fail-opens on access denied;
    /// FirstLogon settle fail-closes after repair/verify.
    /// </summary>
    internal static DmaSetupRegionLatch EnsureDmaSetupRegion(
        IDmaSetupRegion? port,
        DmaSetupRegionPolicy policy)
    {
        if (port is null)
        {
            return new DmaSetupRegionLatch(DmaSetupRegionLatchKind.MissingPort, null, null);
        }

        try
        {
            DmaSetupRegionEnsureResult result = port.EnsureIreland();
            return new DmaSetupRegionLatch(DmaSetupRegionLatchKind.Ok, result, null);
        }
        catch (Exception ex) when (
            policy == DmaSetupRegionPolicy.MachineSetup
            && ex is UnauthorizedAccessException or SecurityException)
        {
            // ponytail: OOBE still holds DeviceRegion during SetupComplete. Exit 1 reseals to Recovery.
            // FirstLogon settle retries the latch; fail-closed stays for verify/null-port failures.
            return new DmaSetupRegionLatch(DmaSetupRegionLatchKind.AccessDeniedSoft, null, null);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new DmaSetupRegionLatch(DmaSetupRegionLatchKind.Failed, null, ex.Message);
        }
    }

    private static void TryReapply(IRegionSnapshot region, DmaSettleTarget target)
    {
        try
        {
            region.Apply(target);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // ponytail: intermediate re-apply fail-open — final snapshot gates
            _ = ex;
        }
    }
}
