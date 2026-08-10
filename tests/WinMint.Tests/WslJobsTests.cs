using System.Text;
using WinMint.Orchestrator;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 23 — metal wsl job at S1 (Plan) + S3 (Run).</summary>
public class WslJobsTests
{
    [Fact]
    public void Plan_emits_wsl_jobs_from_packages_wsl()
    {
        Profile profile = Parse(MinimalJson(wsl: ["Ubuntu"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor ubuntu = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "wsl");
        Assert.Equal("wsl.Ubuntu", ubuntu.Id);
        Assert.Equal("Ubuntu", ubuntu.PackageId);
        Assert.Equal("store", ubuntu.WslInstallKind);
        Assert.False(ubuntu.NeedsReboot);
    }

    [Fact]
    public void Plan_nixos_wsl_emits_fromFile_metadata()
    {
        Profile profile = Parse(MinimalJson(wsl: ["NixOS-WSL"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor nix = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "wsl");
        Assert.Equal("NixOS", nix.PackageId);
        Assert.Equal("fromFile", nix.WslInstallKind);
        Assert.Equal("nix-community/NixOS-WSL", nix.WslFromFileRepo);
        Assert.Contains("nixos.aarch64.wsl", nix.WslFromFileAssetNames!);
    }

    [Fact]
    public void Plan_wslNeedsReboot_subset_emits_needsReboot()
    {
        Profile profile = Parse(MinimalJson(wsl: ["Ubuntu"], wslNeedsReboot: ["Ubuntu"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.True(Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "wsl").NeedsReboot);
    }

    [Fact]
    public void Plan_wslNeedsReboot_id_not_in_wsl_fails_closed()
    {
        Profile profile = Parse(MinimalJson(wsl: ["Ubuntu"], wslNeedsReboot: ["Debian"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.wslNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public void Shell_wsl_runs_install_distro_argv()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("wsl.Ubuntu", "wsl", PackageId: "Ubuntu")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Contains(
            processes.Starts,
            s => s.FileName.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase)
                && s.Arguments is ["--install", "-d", "Ubuntu", "--no-launch"]);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Issues.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }

    private static string MinimalJson(
        IReadOnlyList<string>? wsl = null,
        IReadOnlyList<string>? wslNeedsReboot = null)
    {
        List<string> fields = [];
        if (wsl is not null)
        {
            fields.Add($"\"wsl\": [{string.Join(",", wsl.Select(id => $"\"{id}\""))}]");
        }

        if (wslNeedsReboot is not null)
        {
            fields.Add(
                $"\"wslNeedsReboot\": [{string.Join(",", wslNeedsReboot.Select(id => $"\"{id}\""))}]");
        }

        string packagesBody = string.Join(",\n                ", fields);
        return $$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
                {{packagesBody}}
              }
            }
            """;
    }
}
