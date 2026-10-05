using System.Security.Cryptography;
using System.Text;

using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>
/// Product-curated host defaults (issue #136 P0): recommended debloat + authored package ids,
/// Windows taskbar, bootstrap account. Preset names never enter Profile JSON (ADR-005).
/// Distinct from Primary <c>samples/sl7.profile.json</c> (#96 freeze).
/// </summary>
public static class CuratedDefaults
{
    public const string BootstrapUsername = "winmint";

    /// <summary>Wizard chip keys for the curated authored package set.</summary>
    public static IReadOnlyList<string> ToolChipKeys { get; } = ["cursor", "zen-browser"];

    public static IReadOnlyList<string> WslTokens { get; } = ["FedoraLinux"];

    public static IReadOnlyList<string> SelectionLabels { get; } =
        ["Windows taskbar", "Cursor", "Zen", "Fedora"];

    public static string NewBootstrapPassword()
    {
        // ponytail: 24 bytes → base64url (~32 chars); enough for AutoLogon bridge until C2
        Span<byte> bytes = stackalloc byte[24];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    /// <summary>
    /// Expand curated defaults into a Profile. Pass <paramref name="passwordPath"/> to author
    /// <c>account.passwordPath</c> (caller writes the secret); otherwise inline <c>account.password</c>.
    /// </summary>
    public static Result<Profile, Failure> TryCreate(
        DmaSettleTarget settle,
        string bootstrapPassword,
        string? passwordPath = null,
        bool requireWifiDuringOobe = true)
    {
        ArgumentNullException.ThrowIfNull(settle);
        if (string.IsNullOrEmpty(bootstrapPassword))
        {
            return Result.Fail<Profile, Failure>(
                new Failure("account.password.required", "Curated bootstrap requires a non-empty password."));
        }

        Result<DebloatExpansion, Failure> debloat = DebloatPresets.TryExpand(DebloatPresets.Recommended);
        if (!debloat.IsOk)
        {
            return Result.Fail<Profile, Failure>(debloat.Error);
        }

        Result<PackageSelection, Failure> tools =
            PackageCatalog.Default.ResolveToolKeys(ToolChipKeys);
        if (!tools.IsOk)
        {
            return Result.Fail<Profile, Failure>(tools.Error);
        }

        Result<IReadOnlyList<string>, Failure> wsl =
            PackageCatalog.Default.ResolveWslTokens(WslTokens);
        if (!wsl.IsOk)
        {
            return Result.Fail<Profile, Failure>(wsl.Error);
        }

        bool usePath = !string.IsNullOrWhiteSpace(passwordPath);
        AccountProfile account = new(
            BootstrapUsername,
            usePath ? null : bootstrapPassword,
            requireWifiDuringOobe,
            usePath ? passwordPath!.Trim() : null);

        return Result.Ok<Profile, Failure>(
            new Profile(
                account,
                new DmaProfile(Enabled: true, settle),
                DebloatMode.Online,
                debloat.Value.RemoveProvisionedAppx,
                tools.Value.WingetInstallIds,
                [],
                tools.Value.ScoopInstallIds,
                [],
                wsl.Value,
                [],
                debloat.Value.RemoveCapabilities,
                debloat.Value.DisableOptionalFeatures));
    }

    /// <summary>Write curated Profile + bootstrap password file for CLI recipe parity.</summary>
    public static Result<CuratedEmitResult, Failure> TryEmit(
        string outputDirectory,
        DmaSettleTarget settle,
        bool requireWifiDuringOobe = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outputDirectory);
        ArgumentNullException.ThrowIfNull(settle);

        string dir = Path.GetFullPath(outputDirectory.Trim());
        Directory.CreateDirectory(dir);
        string passwordFileName = "bootstrap.password";
        string passwordPath = Path.Combine(dir, passwordFileName);
        string profilePath = Path.Combine(dir, "winmint.profile.json");
        string password = NewBootstrapPassword();

        Result<Profile, Failure> created = TryCreate(
            settle,
            password,
            passwordPath: passwordFileName,
            requireWifiDuringOobe);
        if (!created.IsOk)
        {
            return Result.Fail<CuratedEmitResult, Failure>(created.Error);
        }

        try
        {
            File.WriteAllText(passwordPath, password, Encoding.UTF8);
            File.WriteAllBytes(profilePath, BuildPlan.SerializeProfile(created.Value));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Result.Fail<CuratedEmitResult, Failure>(
                new Failure("curatedDefaults.emit.failed", ex.Message));
        }

        return Result.Ok<CuratedEmitResult, Failure>(
            new CuratedEmitResult(profilePath, passwordPath));
    }
}

public sealed record CuratedEmitResult(string ProfilePath, string PasswordPath);
