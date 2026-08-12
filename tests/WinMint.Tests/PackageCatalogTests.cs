using WinMint.Orchestrator;
using WinMint.Contracts;

namespace WinMint.Tests;

public class PackageCatalogTests
{
    [Fact]
    public void Default_catalog_resolves_zen_browser_chip_to_winget_id()
    {
        PackageCatalog catalog = PackageCatalog.Default;
        Result<PackageSelection, Failure> selection = catalog.ResolveToolKeys(["zen-browser"]);
        Assert.True(selection.IsOk);
        Assert.Equal("Zen-Team.Zen-Browser", Assert.Single(selection.Value.WingetInstallIds));
    }

    [Fact]
    public void Catalog_contains_fancywm_stub()
    {
        Assert.True(PackageCatalog.Default.TryGetToolByKey("fancywm", out PackageToolEntry? tool));
        Assert.Equal(PackageToolSource.Winget, tool!.Source);
        Assert.False(string.IsNullOrWhiteSpace(tool.InstallId));
    }

    [Fact]
    public void Default_catalog_splits_winget_and_scoop_shell_tools()
    {
        Result<PackageSelection, Failure> selection = PackageCatalog.Default.ResolveToolKeys(["windhawk", "komorebi"]);
        Assert.True(selection.IsOk);
        Assert.Contains("RamenSoftware.Windhawk", selection.Value.WingetInstallIds);
        Assert.Contains("komorebi", selection.Value.ScoopInstallIds);
    }

    [Fact]
    public void ResolveToolKeys_unknown_key_returns_failure()
    {
        Result<PackageSelection, Failure> result = PackageCatalog.Default.ResolveToolKeys(["not-a-real-chip"]);
        Assert.False(result.IsOk);
        Assert.Equal("packages.catalog.unknown", result.Error.Code);
    }

    [Fact]
    public void ResolveWslTokens_unknown_token_returns_failure()
    {
        Result<IReadOnlyList<string>, Failure> result = PackageCatalog.Default.ResolveWslTokens(["NotADistro"]);
        Assert.False(result.IsOk);
        Assert.Equal("packages.catalog.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_fails_closed_on_unknown_winget_id()
    {
        Profile profile = LabProfile(winget: ["Not.In.Catalog"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);
        Assert.False(result.IsOk);
        Assert.Equal("packages.catalog.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_emits_winget_arch_arm64_on_arm64_image()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });
        Assert.True(result.IsOk);
        Assert.NotNull(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Winget);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.PackageAuditNative);
        using System.Text.Json.JsonDocument doc = System.Text.Json.JsonDocument.Parse(result.Value.WingetImportJson);
        System.Text.Json.JsonElement pkg = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")[0];
        Assert.Equal("--architecture arm64", pkg.GetProperty("InitialOverrideArguments").GetString());
    }

    [Fact]
    public void Wizard_resolve_maps_cursor_and_fedora()
    {
        Result<PackageSelection, Failure> selection = Wizard.WizardSession.ResolvePackageChips(
            [],
            ["cursor"],
            [],
            ["FedoraLinux"]);
        Assert.True(selection.IsOk);
        Assert.Equal("Anysphere.Cursor", Assert.Single(selection.Value.WingetInstallIds));
        Assert.Equal("FedoraLinux", Assert.Single(selection.Value.WslProfileTokens));
    }

    [Fact]
    public void Repo_packages_json_loads_and_matches_embedded_catalog()
    {
        string path = Path.Combine(TestRepo.Root, "config", "packages.json");
        Assert.True(File.Exists(path), $"Missing repo manifest: {path}");

        Result<PackageCatalog, Failure> diskLoad = PackageCatalog.TryLoadFromFile(path);
        Assert.True(diskLoad.IsOk);
        PackageCatalog fromDisk = diskLoad.Value;
        Result<PackageSelection, Failure> diskZen = fromDisk.ResolveToolKeys(["zen-browser"]);
        Result<PackageSelection, Failure> embeddedZen = PackageCatalog.Default.ResolveToolKeys(["zen-browser"]);
        Assert.True(diskZen.IsOk);
        Assert.True(embeddedZen.IsOk);
        Assert.Equal(embeddedZen.Value.WingetInstallIds, diskZen.Value.WingetInstallIds);
    }

    [Fact]
    public void Sl7_style_profile_plans_with_strict_native_audit_job()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "Zen-Team.Zen-Browser"]);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64", PackageAuditStrict = true });
        Assert.True(result.IsOk);
        ProvisionJob audit = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.PackageAuditNative);
        Assert.True(audit.AuditStrict);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
    }

    private static Profile LabProfile(IReadOnlyList<string>? winget = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            winget ?? [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

}
