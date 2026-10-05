using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class WingetConfigurationExportTests
{
    [Fact]
    public void ExportPlan_writes_configuration_winget_beside_import()
    {
        Profile profile = Lab() with { WingetPackages = [ProductPosture.BraveWingetId] };
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-cfg-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.True(HostCompile.ExportPlan(host.Value, dest).IsOk);
            Assert.True(File.Exists(Path.Combine(dest, "winget-import.json")));
            string cfg = Path.Combine(dest, ServicingWorkspace.WingetConfigurationFileName);
            Assert.True(File.Exists(cfg));
            string yaml = File.ReadAllText(cfg);
            Assert.Contains("Microsoft.WinGet.DSC/WinGetPackage", yaml, StringComparison.Ordinal);
            Assert.Contains(ProductPosture.BraveWingetId, yaml, StringComparison.Ordinal);
            Assert.Contains("configurationVersion: 0.2.0", yaml, StringComparison.Ordinal);
            Assert.DoesNotContain("Quiet", yaml, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("HideFirstRunExperience", yaml, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    [Fact]
    public void ExportPlan_omits_configuration_winget_when_no_winget_packages()
    {
        // amd64: plan has winget jobs but no winget-import.json (import is arm64-only).
        Profile profile = Lab() with { WingetPackages = [] };
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(
            profile,
            new HostComposeOptions(ImageArchitecture: "amd64"));
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
        Assert.True(
            host.Value.Artifacts.WingetImportJson is null
            || host.Value.Artifacts.WingetImportJson.Length == 0);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-nocfg-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.True(HostCompile.ExportPlan(host.Value, dest).IsOk);
            Assert.False(File.Exists(Path.Combine(dest, ServicingWorkspace.WingetConfigurationFileName)));
            Assert.False(File.Exists(Path.Combine(dest, "winget-import.json")));
        }
        finally
        {
            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    private static Profile Lab() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);
}
