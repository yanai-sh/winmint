using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PackageCatalogTests
{
    [Fact]
    public void Default_catalog_resolves_zen_browser_chip_to_winget_id()
    {
        PackageCatalog catalog = PackageCatalog.Default;
        PackageSelection selection = catalog.ResolveToolKeys(["zen-browser"]);
        Assert.Equal("Zen-Team.Zen-Browser", Assert.Single(selection.WingetInstallIds));
    }

    [Fact]
    public void Catalog_contains_fancywm_stub()
    {
        Assert.True(PackageCatalog.Default.TryGetToolByKey("fancywm", out PackageToolEntry? tool));
        Assert.Equal("winget", tool!.Source);
        Assert.False(string.IsNullOrWhiteSpace(tool.InstallId));
    }

    [Fact]
    public void Default_catalog_splits_winget_and_scoop_shell_tools()
    {
        PackageSelection selection = PackageCatalog.Default.ResolveToolKeys(["windhawk", "komorebi"]);
        Assert.Contains("RamenSoftware.Windhawk", selection.WingetInstallIds);
        Assert.Contains("komorebi", selection.ScoopInstallIds);
    }

    [Fact]
    public void Plan_fails_closed_on_unknown_winget_id()
    {
        Profile profile = LabProfile(winget: ["Not.In.Catalog"]);
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);
        Assert.False(result.IsOk);
        Assert.Equal("packages.catalog.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_emits_winget_arch_arm64_on_arm64_image()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor"]);
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });
        Assert.True(result.IsOk);
        Assert.NotNull(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "winget.import");
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "winget");
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "package.auditNative");
        using System.Text.Json.JsonDocument doc = System.Text.Json.JsonDocument.Parse(result.Value.WingetImportJson);
        System.Text.Json.JsonElement pkg = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")[0];
        Assert.Equal("--architecture arm64", pkg.GetProperty("InitialOverrideArguments").GetString());
    }

    [Fact]
    public void Wizard_resolve_maps_cursor_and_fedora()
    {
        PackageSelection selection = Wizard.WizardSession.ResolvePackageChips(
            [],
            ["cursor"],
            [],
            ["FedoraLinux"]);
        Assert.Equal("Anysphere.Cursor", Assert.Single(selection.WingetInstallIds));
        Assert.Equal("FedoraLinux", Assert.Single(selection.WslProfileTokens));
    }

    [Fact]
    public void Repo_packages_json_loads_and_matches_embedded_catalog()
    {
        string path = Path.Combine(FindRepoRoot(), "config", "packages.json");
        Assert.True(File.Exists(path), $"Missing repo manifest: {path}");

        PackageCatalog fromDisk = PackageCatalog.LoadFromFile(path);
        PackageSelection diskZen = fromDisk.ResolveToolKeys(["zen-browser"]);
        PackageSelection embeddedZen = PackageCatalog.Default.ResolveToolKeys(["zen-browser"]);
        Assert.Equal(embeddedZen.WingetInstallIds, diskZen.WingetInstallIds);
    }

    [Fact]
    public void Sl7_style_profile_plans_with_strict_native_audit_job()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "Zen-Team.Zen-Browser"]);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64", PackageAuditStrict = true });
        Assert.True(result.IsOk);
        JobDescriptor audit = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "package.auditNative");
        Assert.True(audit.AuditStrict);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "winget.import");
    }

    private static Profile LabProfile(IReadOnlyList<string>? winget = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
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

    private static string FindRepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "config", "packages.json")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException("repo root not found");
    }
}
