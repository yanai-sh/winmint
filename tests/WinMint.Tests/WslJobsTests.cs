using System.Text;
using WinMint.Orchestrator;
using WinMint.Contracts;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>WSL jobs — Microsoft Dev Config platform → reboot → distro semantics.</summary>
public class WslJobsTests
{
    [Fact]
    public void Plan_emits_wsl_platform_before_distro_jobs()
    {
        Profile profile = Parse(MinimalJson(wsl: ["Ubuntu"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor[] wslJobs = result.Value.Jobs.Jobs
            .Where(j => j.Kind is ProvisionJobKind.Wsl or ProvisionJobKind.WslPlatform)
            .ToArray();
        Assert.Equal(2, wslJobs.Length);
        Assert.Equal(ProvisionJobKind.WslPlatform, wslJobs[0].Kind);
        Assert.Equal("wsl.platform", wslJobs[0].Id);
        Assert.Equal(ProvisionJobKind.Wsl, wslJobs[1].Kind);
        Assert.Equal("wsl.Ubuntu", wslJobs[1].Id);
        Assert.Equal("Ubuntu", wslJobs[1].PackageId);
        Assert.Equal(WslInstallKind.Store, wslJobs[1].WslInstallKind);
        Assert.False(wslJobs[1].NeedsReboot);
    }

    [Fact]
    public void Plan_nixos_wsl_emits_fromFile_metadata()
    {
        Profile profile = Parse(MinimalJson(wsl: ["NixOS-WSL"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WslPlatform);
        JobDescriptor nix = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl);
        Assert.Equal("NixOS", nix.PackageId);
        Assert.Equal(WslInstallKind.FromFile, nix.WslInstallKind);
        Assert.Equal("nix-community/NixOS-WSL", nix.WslFromFileRepo);
        Assert.Contains("nixos.aarch64.wsl", nix.WslFromFileAssetNames!);
    }

    [Fact]
    public void Plan_wslNeedsReboot_subset_emits_needsReboot()
    {
        Profile profile = Parse(MinimalJson(wsl: ["Ubuntu"], wslNeedsReboot: ["Ubuntu"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.True(Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl).NeedsReboot);
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
    public async Task Shell_wsl_platform_ready_skips_install()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform)]),
            Env(processes, evidence, isWslPlatformReady: static () => true),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.DoesNotContain(
            processes.Starts,
            s => s.FileName.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase));
        Assert.Contains("jobs.wsl.platform.ready", evidence.Documents[^1].Phases);
    }

    [Fact]
    public async Task Shell_wsl_platform_missing_installs_and_reboots_on_3010()
    {
        RecordingProcessHost processes = new()
        {
            OnRun = static (file, args) =>
            {
                if (file.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase)
                    && args is ["--install", "--no-distribution"])
                {
                    return new ProcessStartResult(3010);
                }

                return new ProcessStartResult(0);
            },
        };
        RecordingEvidenceSink evidence = new();
        RecordingCheckpoints checkpoints = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle(jobs: [new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform)]),
            Env(processes, evidence, checkpoints: checkpoints, isWslPlatformReady: static () => false),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, result.Outcome);
        Assert.Equal("jobs.reboot", result.FinalStatus.Code);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
        Assert.Contains(
            processes.Starts,
            s => s.FileName.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase)
                && s.Arguments is ["--install", "--no-distribution"]);
    }

    [Fact]
    public async Task Shell_wsl_runs_install_distro_argv_and_suppresses_oobe()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        bool oobeSuppressed = false;

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("wsl.Ubuntu", ProvisionJobKind.Wsl, PackageId: "Ubuntu")]),
            Env(
                processes,
                evidence,
                suppressWslOobe: () => oobeSuppressed = true),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.True(oobeSuppressed);
        Assert.Contains(
            processes.Starts,
            s => s.FileName.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase)
                && s.Arguments is ["--install", "-d", "Ubuntu", "--no-launch"]);
    }

    [Fact]
    public async Task Shell_wsl_distro_exit_3010_requests_reboot()
    {
        RecordingProcessHost processes = new()
        {
            OnRun = static (_, _) => new ProcessStartResult(3010),
        };
        RecordingEvidenceSink evidence = new();
        RecordingCheckpoints checkpoints = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle(
                jobs: [new ProvisionJob("wsl.Ubuntu", ProvisionJobKind.Wsl, PackageId: "Ubuntu")]),
            Env(processes, evidence, checkpoints: checkpoints, suppressWslOobe: static () => { }),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, result.Outcome);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
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
                {{packagesBody}}
              }
            }
            """;
    }
}
