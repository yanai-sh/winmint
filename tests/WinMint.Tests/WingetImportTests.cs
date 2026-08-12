using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Contracts;

namespace WinMint.Tests;

public class WingetImportTests
{
    [Fact]
    public void Plan_arm64_winget_emits_import_job_and_json_not_per_id_jobs()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "jqlang.jq"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        Assert.NotNull(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Winget);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.PackageAuditNative);
    }

    [Fact]
    public void Plan_non_arm64_emits_individual_winget_jobs()
    {
        Profile profile = LabProfile(winget: ["jqlang.jq"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        Assert.Null(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "jqlang.jq" });
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
    }

    [Fact]
    public void Import_json_includes_arm64_override_arguments()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        Assert.NotNull(result.Value.WingetImportJson);
        using JsonDocument doc = JsonDocument.Parse(result.Value.WingetImportJson);
        JsonElement packages = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages");
        Assert.Contains(
            packages.EnumerateArray(),
            pkg => pkg.GetProperty("PackageIdentifier").GetString() == "Anysphere.Cursor"
                && pkg.GetProperty("InitialOverrideArguments").GetString() == "--architecture arm64");
    }

    [Fact]
    public void Plan_same_inputs_emit_identical_import_bytes()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor"]);
        RunOptions options = new() { ImageArchitecture = "arm64" };

        Result<BuildArtifacts, Failure> first = BuildPlan.Plan(profile, options);
        Result<BuildArtifacts, Failure> second = BuildPlan.Plan(profile, options);

        Assert.True(first.IsOk);
        Assert.True(second.IsOk);
        Assert.Equal(first.Value.WingetImportJson, second.Value.WingetImportJson);
        using JsonDocument doc = JsonDocument.Parse(first.Value.WingetImportJson!);
        Assert.Equal(DateTimeOffset.UnixEpoch, doc.RootElement.GetProperty("CreationDate").GetDateTimeOffset());
    }

    [Fact]
    public void Plan_canonicalizes_profile_install_id_and_preserves_reboot_lookup()
    {
        Profile profile = LabProfile(winget: ["anysphere.cursor"]) with
        {
            WingetNeedsReboot = ["ANYSPHERE.CURSOR"],
        };

        Result<BuildArtifacts, Failure> amd64 = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64" });
        Result<BuildArtifacts, Failure> arm64 = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64", PackageAuditStrict = true });

        Assert.True(amd64.IsOk, amd64.IsOk ? null : amd64.Error.Message);
        Assert.True(arm64.IsOk, arm64.IsOk ? null : arm64.Error.Message);
        Assert.Contains(
            amd64.Value.EffectivePackages,
            package => package is
            {
                ResolvedInstallId: "Anysphere.Cursor",
                Origin: EffectivePackageOrigin.Profile,
                NeedsReboot: true,
            });
        Assert.Contains(
            amd64.Value.Jobs.Jobs,
            job => job is
            {
                Id: "winget.Anysphere.Cursor",
                PackageId: "Anysphere.Cursor",
                NeedsReboot: true,
            });

        ProvisionJob import = Assert.Single(
            arm64.Value.Jobs.Jobs,
            job => job.Kind == ProvisionJobKind.WingetImport);
        Assert.True(import.NeedsReboot);
        using JsonDocument doc = JsonDocument.Parse(arm64.Value.WingetImportJson!);
        Assert.Contains(
            doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages").EnumerateArray(),
            package => package.GetProperty("PackageIdentifier").GetString() == "Anysphere.Cursor");
        ProvisionJob audit = Assert.Single(
            arm64.Value.Jobs.Jobs,
            job => job.Kind == ProvisionJobKind.PackageAuditNative);
        Assert.Contains("Anysphere.Cursor", audit.PackageId!.Split(';'), StringComparer.Ordinal);
    }

    [Fact]
    public void Plan_effective_facts_are_ordered_deduped_and_agree_with_package_jobs()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "git.mingit"]) with
        {
            WingetNeedsReboot = ["Anysphere.Cursor"],
            ScoopPackages = ["neovim", "STARSHIP"],
            WslDistros = ["NixOS-WSL"],
            WslNeedsReboot = ["NixOS-WSL"],
        };

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64", PackageAuditStrict = true });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        EffectivePackageFact[] facts = result.Value.EffectivePackages.ToArray();
        Assert.Equal(ProductPosture.WingetIds[0], facts[0].ResolvedInstallId);
        Assert.Equal(EffectivePackageOrigin.ProductPosture, facts[0].Origin);
        Assert.Equal(1, facts.Count(f => f.ResolvedInstallId.Equals("Git.MinGit", StringComparison.OrdinalIgnoreCase)));
        Assert.Contains(
            facts,
            f => f is
            {
                Source: EffectivePackageSource.Winget,
                ResolvedInstallId: "Anysphere.Cursor",
                Origin: EffectivePackageOrigin.Profile,
                NeedsReboot: true,
            });
        Assert.Contains(
            facts,
            f => f is
            {
                Source: EffectivePackageSource.Scoop,
                ResolvedInstallId: "starship",
                Origin: EffectivePackageOrigin.ProductPosture,
            });
        Assert.Contains(
            facts,
            f => f is
            {
                Source: EffectivePackageSource.Wsl,
                ResolvedInstallId: "NixOS",
                Origin: EffectivePackageOrigin.Profile,
                NeedsReboot: true,
            });

        ProvisionJob[] jobs = result.Value.Jobs.Jobs.ToArray();
        int import = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        int scoop = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        int shell = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.ShellStamp);
        int platform = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.WslPlatform);
        int distro = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.Wsl);
        int audit = Array.FindIndex(jobs, j => j.Kind == ProvisionJobKind.PackageAuditNative);
        Assert.True(import < scoop && scoop < shell && shell < platform && platform < distro && distro < audit);
        Assert.True(jobs[import].NeedsReboot);
        Assert.True(jobs[distro].NeedsReboot);
        using JsonDocument importDoc = JsonDocument.Parse(result.Value.WingetImportJson!);
        Assert.Equal(
            facts.Where(f => f.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store)
                .Select(f => f.ResolvedInstallId),
            importDoc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")
                .EnumerateArray()
                .Select(package => package.GetProperty("PackageIdentifier").GetString()));
        Assert.Equal(
            facts.Where(f => f.Source == EffectivePackageSource.Scoop).Select(f => f.ResolvedInstallId),
            jobs[scoop].PackageId!.Split(';'));
        Assert.Equal(
            facts.Where(f => f.Source == EffectivePackageSource.Wsl).Select(f => f.ResolvedInstallId),
            jobs.Where(j => j.Kind == ProvisionJobKind.Wsl).Select(j => j.PackageId));
        Assert.Equal(
            facts.Where(f => f.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store)
                .Select(f => f.ResolvedInstallId),
            jobs[audit].PackageId!.Split(';'));
    }

    private static Profile LabProfile(IReadOnlyList<string> winget) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            winget,
            [],
            [],
            [],
            [],
            [],
            [],
            []);
}
