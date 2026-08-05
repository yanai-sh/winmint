namespace WinMint.Orchestrator;

/// <summary>Parsed Profile document (winmint.profile/v1). Field names frozen in ticket 01; debloat in ticket 11; OOBE Wi‑Fi via account.requireWifiDuringOobe (BUILDPLAN); packages.winget in ticket 16; wingetNeedsReboot in ticket 17; packages.scoop in ticket 18; capabilities/features in ticket 20; packages.wsl in ticket 23; policies in ADR-009.</summary>
public sealed record Profile(
    AccountProfile Account,
    DmaProfile Dma,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> WingetPackages,
    /// <summary>Subset of <see cref="WingetPackages"/> that emit <c>needsReboot: true</c> on Plan jobs.</summary>
    IReadOnlyList<string> WingetNeedsReboot,
    IReadOnlyList<string> ScoopPackages,
    /// <summary>Subset of <see cref="ScoopPackages"/> that emit <c>needsReboot: true</c> on Plan jobs.</summary>
    IReadOnlyList<string> ScoopNeedsReboot,
    IReadOnlyList<string> WslDistros,
    /// <summary>Subset of <see cref="WslDistros"/> that emit <c>needsReboot: true</c> on Plan jobs.</summary>
    IReadOnlyList<string> WslNeedsReboot,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures,
    /// <summary>Optional; null/omit ⇒ <see cref="PoliciesProfile.Defaults"/>.</summary>
    PoliciesProfile? Policies = null,
    /// <summary>Optional Surface Catalog driver injection (issue 63); null/omit ⇒ no driver stages.</summary>
    DriversProfile? Drivers = null)
{
    public PoliciesProfile EffectivePolicies => Policies ?? PoliciesProfile.Defaults;
}

/// <summary>Surface Catalog driver selection (winmint.profile/v1 drivers block).</summary>
public sealed record DriversProfile(string Source, string DeviceId);

public sealed record AccountProfile(
    string Username,
    string? Password,
    /// <summary>
    /// When true, Autounattend leaves the OOBE Network page visible (<c>HideWirelessSetupInOOBE=false</c>).
    /// Local account + <c>HideOnlineAccountScreens</c> still come from the ISO. Default true (metal);
    /// Smoke Profiles set false for headless Hyper‑V.
    /// </summary>
    bool RequireWifiDuringOobe,
    /// <summary>Host path to password file (issue 56). Resolved at parse; never an environment variable.</summary>
    string? PasswordPath = null);

/// <summary>Wire form of account.mode in profile JSON. Only localAutoLogon is supported.</summary>
public static class AccountModeWire
{
    public const string LocalAutoLogon = "localAutoLogon";
}

public sealed record DmaProfile(
    bool Enabled,
    DmaSettleTarget Settle);

public sealed record DmaSettleTarget(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);
