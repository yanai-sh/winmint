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
    public async Task Shell_nilesoft_winget_nudges_explorer_before_install()
    {
        // Official winget install → WiX MSI OnInstall: shell.exe -restart needs an explorer process.
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };
        int explorerStarts = 0;
        bool explorerRunning = false;
        FakeGuestMachine guest = new()
        {
            Processes = processes,
            Appx = appx,
            IsExplorerProcessRunningCallback = () => explorerRunning,
            TryStartExplorerIfMissingCallback = () =>
            {
                explorerStarts++;
                explorerRunning = true;
            },
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob(
                "winget.Nilesoft.Shell",
                ProvisionJobKind.Winget,
                PackageId: PackageIds.NilesoftShell)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        // Handoff also calls TryStartExplorerIfMissing after jobs.
        Assert.True(explorerStarts >= 1);
        Assert.Single(processes.Starts);
        Assert.Contains("--silent", processes.Starts[0].Arguments);
        Assert.Equal(PackageIds.NilesoftShell, processes.Starts[0].Arguments[2]);
        Assert.Contains("jobs.winget.Nilesoft.Shell.explorerNudge", evidence.Documents[0].Phases);
    }

    [Fact]
    public async Task Shell_nilesoft_winget_import_nudges_explorer_before_install()
    {
        // Same MSI OnInstall hang via WingetImport package list (not a discrete Winget job).
        string importPath = BundleLoader.DefaultGuestWingetImportPath;
        Directory.CreateDirectory(Path.GetDirectoryName(importPath)!);
        string? previous = File.Exists(importPath) ? File.ReadAllText(importPath) : null;
        try
        {
            File.WriteAllText(
                importPath,
                $$"""
                {
                  "Sources": [
                    {
                      "Packages": [
                        { "PackageIdentifier": "{{PackageIds.NilesoftShell}}" }
                      ]
                    }
                  ]
                }
                """);

            RecordingProcessHost processes = new();
            RecordingEvidenceSink evidence = new();
            RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };
            int explorerStarts = 0;
            bool explorerRunning = false;
            FakeGuestMachine guest = new()
            {
                Processes = processes,
                Appx = appx,
                IsExplorerProcessRunningCallback = () => explorerRunning,
                TryStartExplorerIfMissingCallback = () =>
                {
                    explorerStarts++;
                    explorerRunning = true;
                },
            };

            SessionResult result = await ProvisioningSession.RunShellAsync(
                Bundle(jobs: [new ProvisionJob("winget.import", ProvisionJobKind.WingetImport)]),
                Env(guest, evidence),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Complete, result.Outcome);
            Assert.True(explorerStarts >= 1);
            Assert.Single(processes.Starts);
            Assert.Equal(PackageIds.NilesoftShell, processes.Starts[0].Arguments[2]);
            Assert.Contains($"jobs.winget.{PackageIds.NilesoftShell}.explorerNudge", evidence.Documents[0].Phases);
        }
        finally
        {
            if (previous is null)
            {
                if (File.Exists(importPath))
                {
                    File.Delete(importPath);
                }
            }
            else
            {
                File.WriteAllText(importPath, previous);
            }
        }
    }

    [Fact]
    public async Task EnsureExplorer_for_nilesoft_is_noop_when_explorer_already_runs()
    {
        int starts = 0;
        FakeGuestMachine guest = new()
        {
            IsExplorerProcessRunningCallback = static () => true,
            TryStartExplorerIfMissingCallback = () => starts++,
        };

        await ProvisioningJobRunner.EnsureExplorerForNilesoftMsiAsync(
            guest,
            TestContext.Current.CancellationToken);

        Assert.Equal(0, starts);
    }

    [Fact]
    public void SmokeDefaults_package_job_timeout_caps_winget_hangs()
    {
        // Official winget path for Nilesoft.Shell; timeout keeps one hung MSI from burning tenure.
        Assert.Equal(TimeSpan.FromMinutes(20), SessionPolicy.SmokeDefaults.PackageJobTimeout);
        Assert.Equal(TimeSpan.FromMinutes(150), SessionPolicy.SmokeDefaults.WallClockTimeout);
    }

    [Fact]
    public void Winget_install_arguments_are_silent_and_noninteractive()
    {
        string[] args = ProvisioningJobRunner.BuildWingetInstallArguments(
            "Nilesoft.Shell",
            "--architecture arm64",
            @"C:\evidence\winget-Nilesoft.Shell.log");

        Assert.Equal("install", args[0]);
        Assert.Contains("--id", args);
        Assert.Contains("Nilesoft.Shell", args);
        Assert.Contains("--silent", args);
        Assert.Contains("--disable-interactivity", args);
        Assert.Contains("--accept-package-agreements", args);
        Assert.Contains("--accept-source-agreements", args);
        Assert.Contains("--architecture", args);
        Assert.Contains("arm64", args);
    }

    [Fact]
    public async Task Shell_winget_job_timeout_fail_opens_and_continues()
    {
        // Official winget install → WiX MSI OnInstall CA hang (Nilesoft): CancelAfter; !PackageStrict continues.
        RecordingProcessHost processes = new() { BlockUntilCancel = TimeSpan.FromSeconds(30) };
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };
        ProvisioningBundle bundle = Bundle(
            jobs: [new ProvisionJob("winget.Nilesoft.Shell", ProvisionJobKind.Winget, PackageId: "Nilesoft.Shell")]) with
        {
            Policy = SessionPolicy.SmokeDefaults with { PackageJobTimeout = TimeSpan.FromMilliseconds(80) },
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            bundle,
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
        Assert.Contains(
            evidence.PackageDocuments,
            d => d.Failures.Any(f => f.JobId == "winget.Nilesoft.Shell"
                && (f.Message?.Contains("timed out", StringComparison.OrdinalIgnoreCase) ?? false)));
    }

    [Fact]
    public async Task Shell_winget_job_aggregate_cancel_fail_opens_not_shell_crash()
    {
        // AOT Process.RunAsync cancel can surface AggregateException(TaskCanceledException).
        RecordingProcessHost processes = new()
        {
            OnRun = static (_, _) => throw new AggregateException(
                new TaskCanceledException("Process.RunAsync canceled.")),
        };
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };
        ProvisioningBundle bundle = Bundle(
            jobs:
            [
                new ProvisionJob("winget.Nilesoft.Shell", ProvisionJobKind.Winget, PackageId: "Nilesoft.Shell"),
                new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq"),
            ]) with
        {
            Policy = SessionPolicy.SmokeDefaults with { PackageJobTimeout = TimeSpan.FromMinutes(20) },
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            bundle,
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Equal(2, processes.Starts.Count);
        Assert.Contains(
            evidence.PackageDocuments,
            d => d.Failures.Any(f => f.JobId == "winget.Nilesoft.Shell"
                && (f.Message?.Contains("timed out", StringComparison.OrdinalIgnoreCase) ?? false)));
    }

    [Fact]
    public async Task Shell_winget_job_timeout_fails_closed_when_strict()
    {
        RecordingProcessHost processes = new() { BlockUntilCancel = TimeSpan.FromSeconds(30) };
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };
        ProvisioningBundle bundle = Bundle(
            jobs: [new ProvisionJob("winget.Nilesoft.Shell", ProvisionJobKind.Winget, PackageId: "Nilesoft.Shell")]) with
        {
            PackageStrict = true,
            Policy = SessionPolicy.SmokeDefaults with { PackageJobTimeout = TimeSpan.FromMilliseconds(80) },
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            bundle,
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.package.timeout", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
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

    [Fact]
    public void Zen_audit_paths_include_the_user_programs_install()
    {
        string expected = Path.Combine(ShellChromeLayout.ZenUserInstallDirectory(), "zen.exe");
        Assert.Contains(expected, ProvisioningJobRunner.GuiBinaryPaths(PackageIds.ZenBrowser));
    }

    [Fact]
    public void Winget_install_arguments_name_the_package_and_keep_a_log()
    {
        string[] args = ProvisioningJobRunner.BuildWingetInstallArguments(
            "Zen-Team.Zen-Browser",
            "--architecture arm64",
            @"C:\evidence\winget-Zen-Team.Zen-Browser.log");

        Assert.Contains("--id", args);
        Assert.Contains("Zen-Team.Zen-Browser", args);
        Assert.Contains("--log", args);
        Assert.Contains(@"C:\evidence\winget-Zen-Team.Zen-Browser.log", args);
        Assert.Contains("--architecture", args);
        Assert.Contains("arm64", args);
        Assert.DoesNotContain("import", args);
    }

    [Fact]
    public async Task Medium_il_accepts_zen_only_when_the_exe_exists()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-zen-test-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        string? downloadDir = null;
        try
        {
            RecordingProcessHost host = new()
            {
                OnRun = (_, args) =>
                {
                    int directory = args.ToList().FindIndex(a => a == "--download-directory");
                    if (directory >= 0 && directory + 1 < args.Count)
                    {
                        downloadDir = args[directory + 1];
                        File.WriteAllBytes(Path.Combine(downloadDir, "helper.exe"), [0x4D, 0x5A]);
                        File.WriteAllBytes(Path.Combine(downloadDir, "zen.installer-arm64.exe"), [0x4D, 0x5A]);
                    }

                    string? installArg = args.FirstOrDefault(a => a.StartsWith("/InstallDirectoryPath=", StringComparison.Ordinal));
                    if (installArg is not null)
                    {
                        string installDir = installArg["/InstallDirectoryPath=".Length..].Trim('"');
                        Directory.CreateDirectory(installDir);
                        File.WriteAllBytes(Path.Combine(installDir, "zen.exe"), [0x4D, 0x5A]);
                    }

                    return new ProcessStartResult(0);
                },
            };

            bool installed = await ProvisioningJobRunner.TryInstallZenUserAsync(
                host,
                "winget.exe",
                elevated: false,
                report: static _ => { },
                TestContext.Current.CancellationToken,
                dir);

            Assert.True(installed);
            Assert.Contains(host.Starts, start => start.FileName.EndsWith("zen.installer-arm64.exe", StringComparison.OrdinalIgnoreCase));
            Assert.DoesNotContain(host.Starts, start => start.FileName.EndsWith("helper.exe", StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            if (downloadDir is not null && Directory.Exists(downloadDir))
            {
                Directory.Delete(downloadDir, recursive: true);
            }

            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Zen_exit_zero_without_the_exe_is_not_installed()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-zen-test-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        string? downloadDir = null;
        try
        {
            RecordingProcessHost host = new()
            {
                OnRun = (_, args) =>
                {
                    int directory = args.ToList().FindIndex(a => a == "--download-directory");
                    if (directory >= 0 && directory + 1 < args.Count)
                    {
                        downloadDir = args[directory + 1];
                        File.WriteAllBytes(Path.Combine(downloadDir, "zen.installer-arm64.exe"), [0x4D, 0x5A]);
                    }

                    return new ProcessStartResult(0);
                },
            };

            bool installed = await ProvisioningJobRunner.TryInstallZenUserAsync(
                host,
                "winget.exe",
                elevated: false,
                report: static _ => { },
                TestContext.Current.CancellationToken,
                dir);

            Assert.False(installed);
        }
        finally
        {
            if (downloadDir is not null && Directory.Exists(downloadDir))
            {
                Directory.Delete(downloadDir, recursive: true);
            }

            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Elevated_zen_stays_on_winget_install()
    {
        RecordingProcessHost host = new();
        bool installed = await ProvisioningJobRunner.TryInstallZenUserAsync(
            host,
            "winget.exe",
            elevated: true,
            report: static _ => { },
            TestContext.Current.CancellationToken,
            Path.GetTempPath());

        Assert.False(installed);
        Assert.Empty(host.Starts);
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
