using System.Text;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class BuildPlanPlanTests
{
    [Fact]
    public void Plan_local_autologon_without_password_uses_default()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Contains(
            AccountProfile.DefaultLocalPassword,
            result.Value.Unattend.Xml,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_dma_on_latches_ireland_and_copies_settle_target()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Contains(BuildPlan.IrelandSetupLocale, artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains(
            @"Control Panel\DeviceRegion"" /v DeviceRegion /t REG_DWORD /d 68 ",
            artifacts.Unattend.Xml,
            StringComparison.Ordinal);
        Assert.Contains(
            @"HKU\.DEFAULT\Control Panel\International\Geo"" /v Nation /t REG_SZ /d 68 ",
            artifacts.Unattend.Xml,
            StringComparison.Ordinal);
        Assert.Contains(
            @"HKU\.DEFAULT\Control Panel\International\Geo"" /v Name /t REG_SZ /d IE ",
            artifacts.Unattend.Xml,
            StringComparison.Ordinal);
        Assert.DoesNotContain(@"Control\Nls\Geo", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.DoesNotContain("windowsPE", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("oobeSystem", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<Name>winmint</Name>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        // Default requireWifiDuringOobe=true → show Network page
        Assert.Contains("<HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.True(artifacts.Account.RequireWifiDuringOobe);
        Assert.True(artifacts.Dma.Enabled);
        Assert.NotNull(artifacts.Dma.Settle);
        Assert.Equal("en-GB", artifacts.Dma.Settle.Locale);
        Assert.Equal(242, artifacts.Dma.Settle.GeoId);
        Assert.Equal("GMT Standard Time", artifacts.Dma.Settle.TimeZoneId);
        Assert.True(artifacts.Dma.Settle.LocationServicesEnabled);
    }

    [Fact]
    public void Plan_require_wifi_false_hides_wireless_oobe()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only",
                "requireWifiDuringOobe": false
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.False(artifacts.Account.RequireWifiDuringOobe);
        Assert.Contains("<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>", artifacts.Unattend.Xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_default_emits_test_lane_opcodes_without_smoke_stubs()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Equal(ImageQualityLane.Test, artifacts.Manifest.ImageQuality);
        Assert.Equal(JobsWire.SchemaVersion, artifacts.Jobs.SchemaVersion);
        Assert.DoesNotContain(artifacts.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Stub);
        Assert.NotEmpty(artifacts.Stages);
        Assert.Equal(
            [
                ServicingOpcode.MountInstallWim,
                ServicingOpcode.StampOfflinePolicies,
                ServicingOpcode.EraseOfflineOneDrive,
                ServicingOpcode.RemoveProvisionedAppx,
                ServicingOpcode.StagePayload,
                ServicingOpcode.StampOfflineDefaultUser,
                ServicingOpcode.StageOobeUnattend,
                ServicingOpcode.StampOfflineShell,
                ServicingOpcode.PatchBootWimApply,
                ServicingOpcode.ExportWim,
                ServicingOpcode.BuildIso,
            ],
            artifacts.Stages);
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == ProvisionJobKind.OneDriveUninstall);
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ReservedStorageDisable);
        Assert.Null(artifacts.Drivers);
        ExportLane export = ExportLane.For(artifacts.Manifest.ImageQuality);
        Assert.Equal("Test", export.Name);
        Assert.Equal("fast", export.Compression);
        Assert.Equal("skip", export.Cleanup);
    }

    [Fact]
    public void Plan_includeSmokeStubs_emits_stub_jobs()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { IncludeSmokeStubs = true });

        Assert.True(result.IsOk);
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: ProvisionJobKind.Stub, Id: "smoke.stub.ready" });
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: ProvisionJobKind.Stub, Id: "smoke.stub.complete" });
        Assert.True(result.Value.Manifest.RequiresNetwork);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
    }

    [Fact]
    public void Plan_smokePlumbing_omits_outbound_packages_and_requiresNetwork_false()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              },
              "packages": {
                "winget": ["Anysphere.Cursor"],
                "wsl": ["Ubuntu"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { IncludeSmokeStubs = true, SmokePlumbing = true });

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.False(artifacts.Manifest.RequiresNetwork);
        Assert.Contains(artifacts.Jobs.Jobs, j => j is { Kind: ProvisionJobKind.Stub, Id: "smoke.stub.ready" });
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WslPlatform);
        Assert.DoesNotContain(artifacts.Jobs.Jobs, j => j.Kind is ProvisionJobKind.Winget or ProvisionJobKind.WingetImport);
        Assert.DoesNotContain(artifacts.Jobs.Jobs, j => j.Kind is ProvisionJobKind.Scoop or ProvisionJobKind.ScoopBatch);
        Assert.DoesNotContain(artifacts.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl);
        Assert.DoesNotContain(
            artifacts.EffectivePackages,
            p => string.Equals(p.ResolvedInstallId, ProductPosture.MinGitWingetId, StringComparison.OrdinalIgnoreCase));
        Assert.Empty(artifacts.EffectiveWinget);
    }

    [Fact]
    public void Plan_smokePlumbing_without_stubs_fails()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { SmokePlumbing = true });

        Assert.False(result.IsOk);
        Assert.Equal("run.smokePlumbing.stubsRequired", result.Error.Code);
    }

    [Fact]
    public void Plan_smokePlumbing_release_fails()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions
            {
                IncludeSmokeStubs = true,
                SmokePlumbing = true,
                ImageQuality = ImageQualityLane.Release,
            });

        Assert.False(result.IsOk);
        Assert.Equal("run.smokePlumbing.testLaneRequired", result.Error.Code);
    }

    [Fact]
    public void Plan_release_lane_export_params_differ_from_test()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageQuality = ImageQualityLane.Release });

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Equal(ImageQualityLane.Release, artifacts.Manifest.ImageQuality);
        ExportLane export = ExportLane.For(artifacts.Manifest.ImageQuality);
        Assert.Equal("Release", export.Name);
        Assert.Equal("max", export.Compression);
        Assert.Equal("full", export.Cleanup);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }
}
