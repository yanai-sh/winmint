using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>AppX remove-list execution venue (issue 71). Absent in Profile JSON ⇒ online.</summary>
public enum DebloatMode
{
    Online,
    Offline,
}

/// <summary>
/// Parsed Profile document (winmint.profile/v1). Field names frozen in ticket 01; debloat in ticket 11; OOBE Wi‑Fi via account.requireWifiDuringOobe (BUILDPLAN); packages.winget in ticket 16; wingetNeedsReboot in ticket 17; packages.scoop in ticket 18; capabilities/features in ticket 20; packages.wsl in ticket 23; policies in ADR-009.
/// <c>*NeedsReboot</c> lists are subsets that emit <c>needsReboot: true</c> on Plan jobs. Null/omit <see cref="Policies"/> ⇒ <see cref="PoliciesProfile.Defaults"/>. Null/omit <see cref="Drivers"/> ⇒ no driver stages.
/// </summary>
public sealed record Profile(
    AccountProfile Account,
    DmaProfile Dma,
    DebloatMode DebloatMode,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> WingetPackages,
    IReadOnlyList<string> WingetNeedsReboot,
    IReadOnlyList<string> ScoopPackages,
    IReadOnlyList<string> ScoopNeedsReboot,
    IReadOnlyList<string> WslDistros,
    IReadOnlyList<string> WslNeedsReboot,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures,
    PoliciesProfile? Policies = null,
    DriversProfile? Drivers = null)
{
    public PoliciesProfile EffectivePolicies => Policies ?? PoliciesProfile.Defaults;
}

/// <summary>
/// Optional Profile <c>policies</c> object (winmint.profile/v1). Omit ⇒ product defaults.
/// AppX Copilot/gaming strip, OneDrive / EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage /
/// MinGit / Nilesoft are product posture (<see cref="ProductPosture"/>), not fields here.
/// <c>DohProvider</c> is an optional DoH id (<c>cloudflare</c>, <c>google</c>, <c>quad9</c>); null/omit ⇒ no DoH job.
/// </summary>
public sealed record PoliciesProfile(
    string? DohProvider = null)
{
    public static PoliciesProfile Defaults { get; } = new();
}

/// <summary>Surface Catalog driver selection (winmint.profile/v1 drivers block).</summary>
public sealed record DriversProfile(string Source, string DeviceId);

/// <summary>
/// Local auto-logon account from Profile JSON.
/// <c>RequireWifiDuringOobe</c>: when true, OobeUnattend leaves the OOBE Network page visible (<c>HideWirelessSetupInOOBE=false</c>).
/// Local account + <c>HideOnlineAccountScreens</c> still come from the ISO. Default true (real hardware);
/// Smoke Profiles set false for headless Hyper‑V.
/// <c>PasswordPath</c> is the authored host path to the password file (issue 56); never an environment variable.
/// </summary>
public sealed record AccountProfile(
    string Username,
    string? Password,
    bool RequireWifiDuringOobe,
    string? PasswordPath = null)
{
    /// <summary>Only supported wire form of account.mode in Profile JSON.</summary>
    public const string LocalAutoLogonMode = "localAutoLogon";
}

public sealed record DmaProfile(
    bool Enabled,
    DmaSettleTarget Settle);
