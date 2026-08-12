using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>AppX remove-list execution venue (issue 71). Absent in Profile JSON ⇒ online.</summary>
public enum DebloatMode
{
    Online,
    Offline,
}

/// <summary>Parsed Profile document (winmint.profile/v1). Field names frozen in ticket 01; debloat in ticket 11; OOBE Wi‑Fi via account.requireWifiDuringOobe (BUILDPLAN); packages.winget in ticket 16; wingetNeedsReboot in ticket 17; packages.scoop in ticket 18; capabilities/features in ticket 20; packages.wsl in ticket 23; policies in ADR-009.</summary>
public sealed record Profile(
    AccountProfile Account,
    DmaProfile Dma,
    DebloatMode DebloatMode,
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

/// <summary>
/// Optional Profile <c>policies</c> object (winmint.profile/v1). Omit ⇒ product defaults.
/// AppX Copilot/gaming strip, OneDrive / EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage /
/// MinGit / Nilesoft are product posture (<see cref="ProductPosture"/>), not fields here.
/// </summary>
public sealed record PoliciesProfile(
    /// <summary>Optional DoH provider id (<c>cloudflare</c>, <c>google</c>, <c>quad9</c>). Null/omit ⇒ no DoH job.</summary>
    string? DohProvider = null)
{
    public static PoliciesProfile Defaults { get; } = new();
}

/// <summary>Surface Catalog driver selection (winmint.profile/v1 drivers block).</summary>
public sealed record DriversProfile(string Source, string DeviceId);

public sealed record AccountProfile(
    string Username,
    string? Password,
    /// <summary>
    /// When true, OobeUnattend leaves the OOBE Network page visible (<c>HideWirelessSetupInOOBE=false</c>).
    /// Local account + <c>HideOnlineAccountScreens</c> still come from the ISO. Default true (real hardware);
    /// Smoke Profiles set false for headless Hyper‑V.
    /// </summary>
    bool RequireWifiDuringOobe,
    /// <summary>Authored host path to password file (issue 56). Materialized by ProfileFile; never an environment variable.</summary>
    string? PasswordPath = null)
{
    /// <summary>Only supported wire form of account.mode in Profile JSON.</summary>
    public const string LocalAutoLogonMode = "localAutoLogon";
}

public sealed record DmaProfile(
    bool Enabled,
    DmaSettleTarget Settle);
