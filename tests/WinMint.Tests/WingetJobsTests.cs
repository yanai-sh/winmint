using System.Text;

using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 16 — winget job at S1 (Plan) + S3 (Run).</summary>
public class WingetJobsTests
{
    [Fact]
    public void Plan_emits_winget_jobs_from_packages_winget()
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
                "winget": ["jqlang.jq", "Microsoft.VisualStudioCode"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64", IncludeSmokeStubs = true });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        IReadOnlyList<ProvisionJob> jobs = result.Value.Jobs.Jobs;
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Stub, Id: "smoke.stub.ready" });
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Stub, Id: "smoke.stub.complete" });
        ProvisionJob jq = Assert.Single(jobs, j => j.Kind == ProvisionJobKind.Winget && j.PackageId == "jqlang.jq");
        Assert.Equal("winget.jqlang.jq", jq.Id);
        ProvisionJob vscode = Assert.Single(jobs, j => j.Kind == ProvisionJobKind.Winget && j.PackageId == "Microsoft.VisualStudioCode");
        Assert.Equal("winget.Microsoft.VisualStudioCode", vscode.Id);
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "Git.MinGit" });
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "Microsoft.PowerShell" });
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "Microsoft.WindowsTerminal" });
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "Microsoft.Coreutils" });
        Assert.Contains(jobs, j => j is { Kind: ProvisionJobKind.Winget, PackageId: "Nilesoft.Shell" });
        Assert.Equal(7, jobs.Count(j => j.Kind == ProvisionJobKind.Winget));
    }

    [Fact]
    public void Plan_without_packages_still_emits_product_constant_winget()
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

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Stub);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.OneDriveUninstall);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ReservedStorageDisable);
        Assert.True(result.Value.Manifest.RequiresNetwork);
    }

    [Fact]
    public void Plan_wingetNeedsReboot_subset_sets_import_job_needsReboot()
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
                "winget": ["jqlang.jq", "Microsoft.VisualStudioCode"],
                "wingetNeedsReboot": ["jqlang.jq"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        ProvisionJob importJob = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.WingetImport);
        Assert.True(importJob.NeedsReboot);
    }

    [Fact]
    public void Plan_wingetNeedsReboot_subset_emits_needsReboot_on_matching_jobs()
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
                "winget": ["jqlang.jq", "Microsoft.VisualStudioCode"],
                "wingetNeedsReboot": ["jqlang.jq"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Code);
        ProvisionJob jq = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "jqlang.jq");
        Assert.True(jq.NeedsReboot);
        ProvisionJob vscode = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "Microsoft.VisualStudioCode");
        Assert.False(vscode.NeedsReboot);
    }

    [Fact]
    public void Plan_wingetNeedsReboot_id_not_in_winget_fails_closed()
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
                "winget": ["jqlang.jq"],
                "wingetNeedsReboot": ["Microsoft.VisualStudioCode"]
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.wingetNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public async Task Shell_winget_job_invokes_expected_argv()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq", WingetArchitecture: "arm64")]),
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
        Assert.Equal(appx.WingetPath, processes.Starts[0].FileName);
        Assert.Equal(
            [
                "install",
                "--id",
                "jqlang.jq",
                "--exact",
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements",
                "--disable-interactivity",
                "--architecture",
                "arm64",
            ],
            processes.Starts[0].Arguments);
        Assert.Contains("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public async Task Shell_winget_job_fails_closed_when_Appx_missing()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.failed", result.FinalStatus.Code);
        Assert.Contains("IAppxPackageManager", result.FinalStatus.Message);
        Assert.Empty(processes.Starts);
    }

    [Fact]
    public async Task Shell_winget_job_fails_closed_when_resolve_returns_null_and_strict()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = null };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]) with { PackageStrict = true },
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.winget.pathMissing", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
        Assert.Contains(ProvisioningSession.DesktopAppInstallerFamilyName, appx.RegisteredFamilyNames);
    }

    [Fact]
    public async Task Shell_winget_job_best_effort_when_resolve_returns_null()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = null };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]),
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Empty(processes.Starts);
    }

    [Fact]
    public async Task Shell_winget_job_registers_app_installer_before_spawn()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new()
        {
            WingetPath = @"C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.0_arm64__8wekyb3d8bbwe\winget.exe",
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]),
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains(
            ProvisioningSession.DesktopAppInstallerFamilyName,
            appx.RegisteredFamilyNames);
        Assert.Single(processes.Starts);
        Assert.Equal(appx.WingetPath, processes.Starts[0].FileName);
    }


    [Fact]
    public async Task Shell_needsReboot_requests_os_reboot_after_checkpoint()
    {
        RecordingProcessHost processes = new();
        RecordingCheckpoints checkpoints = new();
        RecordingSystemReboot reboot = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("smoke.stub.reboot", ProvisionJobKind.Stub, NeedsReboot: true)]),
            Env(processes, evidence, checkpoints, reboot),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, result.Outcome);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
        Assert.True(reboot.Requested);
        Assert.Equal("Reboot", evidence.Documents[0].Outcome);
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
