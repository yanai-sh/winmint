using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ShellChromeJobTests
{
    [Fact]
    public void Plan_emits_shell_chrome_after_wsl()
    {
        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            ["Anysphere.Cursor"],
            [],
            [],
            [],
            ["FedoraLinux"],
            [],
            [],
            []);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        IReadOnlyList<ProvisionJob> jobs = result.Value.Jobs.Jobs;
        int lastWsl = jobs.ToList().FindLastIndex(j => j.Kind is ProvisionJobKind.Wsl or ProvisionJobKind.WslPlatform);
        int chrome = jobs.ToList().FindIndex(j => j.Id == "shell.chrome" && j.Kind == ProvisionJobKind.ShellChrome);
        Assert.True(lastWsl >= 0);
        Assert.True(chrome > lastWsl);
    }

    [Fact]
    public async Task Shell_chrome_records_request_and_emits_phase()
    {
        FakeGuestMachine guest = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        ShellChromeRequest request = Assert.Single(guest.ShellChromeRequests);
        Assert.False(request.FailOpen);
        Assert.Contains("shell.chrome", evidence.Documents[^1].Phases);
    }

    [Fact]
    public async Task Shell_chrome_fails_closed_when_apply_returns_false()
    {
        FakeGuestMachine guest = new()
        {
            ApplyShellChromeCallback = request => !request.FailOpen ? false : true,
        };
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle(jobs: [new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.DoesNotContain("shell.chrome", evidence.Documents[^1].Phases);
    }

    [Fact]
    public async Task Fail_open_applies_baseline_chrome_and_stays_failed()
    {
        RecordingProcessHost processes = new()
        {
            OnRun = static (file, args) =>
            {
                if (file.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase)
                    && args is ["--install", "--no-distribution"])
                {
                    return new ProcessStartResult(1);
                }

                return new ProcessStartResult(0);
            },
        };
        RecordingEvidenceSink evidence = new();
        FakeGuestMachine guest = new()
        {
            Processes = processes,
            IsWslPlatformReadyCallback = static () => false,
            IsHypervisorGuestCallback = static () => false,
            ApplyShellChromeCallback = static _ =>
                throw new InvalidOperationException("simulated chrome failure"),
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle(jobs: [new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        ShellChromeRequest request = Assert.Single(guest.ShellChromeRequests);
        Assert.True(request.FailOpen);
        Assert.Empty(request.SelectedWingetIds);
        Assert.DoesNotContain("shell.chrome", evidence.Documents[^1].Phases);
    }

    [Fact]
    public void Import_file_cursor_and_zen_reach_selected_winget_ids()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-chrome-import-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string importPath = Path.Combine(dir, "winget-import.json");
        try
        {
            File.WriteAllText(
                importPath,
                """
                {
                  "Sources": [
                    {
                      "Packages": [
                        { "PackageIdentifier": "Git.Git" },
                        { "PackageIdentifier": "Anysphere.Cursor" },
                        { "PackageIdentifier": "Zen-Team.Zen-Browser" }
                      ]
                    }
                  ]
                }
                """);

            IReadOnlyList<string> ids = ProvisioningJobRunner.CollectSelectedWingetIds(
                [new ProvisionJob("winget.import", ProvisionJobKind.WingetImport)],
                importPath);

            Assert.Contains(ShellChromeLayout.CursorWingetId, ids);
            Assert.Contains(ShellChromeLayout.ZenWingetId, ids);
            Assert.DoesNotContain("Git.Git", ids);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Import_file_absent_does_not_select_cursor_or_zen()
    {
        IReadOnlyList<string> ids = ProvisioningJobRunner.CollectSelectedWingetIds(
            [new ProvisionJob("winget.import", ProvisionJobKind.WingetImport)],
            Path.Combine(Path.GetTempPath(), "winmint-missing-import-" + Guid.NewGuid().ToString("N") + ".json"));

        Assert.DoesNotContain(ShellChromeLayout.CursorWingetId, ids);
        Assert.DoesNotContain(ShellChromeLayout.ZenWingetId, ids);
    }

    [Fact]
    public void Corrupt_import_file_throws_and_is_not_swallowed()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-chrome-badimport-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string importPath = Path.Combine(dir, "winget-import.json");
        try
        {
            File.WriteAllText(importPath, "{ not-json");

            Assert.ThrowsAny<System.Text.Json.JsonException>(() =>
                ProvisioningJobRunner.CollectSelectedWingetIds(
                    [new ProvisionJob("winget.import", ProvisionJobKind.WingetImport)],
                    importPath));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
