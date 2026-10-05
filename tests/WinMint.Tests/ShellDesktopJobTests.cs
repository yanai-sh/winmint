using System.IO.Compression;

using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ShellDesktopJobTests
{
    [Fact]
    public void Plan_emits_shell_desktop_after_chrome_when_yasb_selected()
    {
        Profile profile = LabProfile(winget: ["AmN.yasb"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });
        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        IReadOnlyList<ProvisionJob> jobs = result.Value.Jobs.Jobs;
        int chrome = jobs.ToList().FindIndex(j => j.Id == "shell.chrome");
        int desktop = jobs.ToList().FindIndex(j => j.Id == "shell.desktop");
        Assert.True(chrome >= 0);
        Assert.True(desktop > chrome);
        Assert.Equal(ProvisionJobKind.ShellDesktop, jobs[desktop].Kind);
    }

    [Fact]
    public void Plan_omits_shell_desktop_for_default_profile()
    {
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            LabProfile(),
            new RunOptions { ImageArchitecture = "arm64" });
        Assert.True(result.IsOk);
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ShellDesktop);
    }

    [Fact]
    public async Task Hash_mismatch_thide_skips_enable_and_job_stays_complete()
    {
        (string guestRoot, string yasbDir, string thideDir) = StageGuestDesktopFixture();
        using PathScope pathScope = PrepPathWithExecutable("yasbc.exe");
        FakeAssetDownload download = new() { VerifiedDownloadPath = null };
        RecordingProcessHost processes = new() { ExitCode = 0 };
        try
        {
            ShellDesktopRequest request = new(
                [ShellDesktopLayout.YasbWingetId],
                processes,
                download,
                guestRoot,
                thideDir,
                yasbDir,
                Path.Combine(Path.GetTempPath(), "komorebi-" + Guid.NewGuid().ToString("N")),
                Path.Combine(Path.GetTempPath(), "whkd-" + Guid.NewGuid().ToString("N")));

            ShellDesktopApplyResult applied = await ShellDesktop.ApplyAsync(
                request,
                TestContext.Current.CancellationToken);
            Assert.False(applied.ThideOk);
            Assert.Contains("thide enable failed", applied.Notes);
            Assert.NotEmpty(download.VerifiedRequests);
        }
        finally
        {
            Directory.Delete(guestRoot, recursive: true);
            if (Directory.Exists(thideDir))
            {
                Directory.Delete(thideDir, recursive: true);
            }

            if (Directory.Exists(yasbDir))
            {
                Directory.Delete(yasbDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Successful_yasb_path_with_fakes_completes()
    {
        (string guestRoot, string yasbDir, string thideDir) = StageGuestDesktopFixture();
        string zipPath = CreateThideZip();
        using PathScope pathScope = PrepPathWithExecutable("yasbc.exe");
        FakeAssetDownload download = new() { VerifiedDownloadPath = zipPath };
        RecordingProcessHost processes = new() { ExitCode = 0 };
        try
        {
            ShellDesktopRequest request = new(
                [ShellDesktopLayout.YasbWingetId],
                processes,
                download,
                guestRoot,
                thideDir,
                yasbDir,
                Path.Combine(Path.GetTempPath(), "komorebi-" + Guid.NewGuid().ToString("N")),
                Path.Combine(Path.GetTempPath(), "whkd-" + Guid.NewGuid().ToString("N")));

            ShellDesktopApplyResult applied = await ShellDesktop.ApplyAsync(
                request,
                TestContext.Current.CancellationToken);
            Assert.True(applied.YasbOk);
            Assert.True(applied.ThideOk);
            Assert.False(applied.RecoveredTaskbar);
            Assert.True(File.Exists(Path.Combine(yasbDir, "config.yaml")));
            Assert.True(File.Exists(Path.Combine(thideDir, "thide.exe")));
        }
        finally
        {
            Directory.Delete(guestRoot, recursive: true);
            File.Delete(zipPath);
            if (Directory.Exists(thideDir))
            {
                Directory.Delete(thideDir, recursive: true);
            }
            if (Directory.Exists(yasbDir))
            {
                Directory.Delete(yasbDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Komorebi_soft_fail_does_not_fail_session()
    {
        (string guestRoot, string yasbDir, string thideDir) = StageGuestDesktopFixture(includeKomorebi: true);
        try
        {
            ShellDesktopRequest request = new(
                [ShellDesktopLayout.KomorebiWingetId],
                new NoopProcesses(),
                null,
                guestRoot,
                thideDir,
                yasbDir,
                Path.Combine(Path.GetTempPath(), "komorebi-" + Guid.NewGuid().ToString("N")),
                Path.Combine(Path.GetTempPath(), "whkd-" + Guid.NewGuid().ToString("N")));

            ShellDesktopApplyResult applied = await ShellDesktop.ApplyAsync(
                request,
                TestContext.Current.CancellationToken);
            Assert.False(applied.KomorebiOk);
            Assert.Contains("komorebi configure failed", applied.Notes);
        }
        finally
        {
            Directory.Delete(guestRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Shell_desktop_records_phase_on_session()
    {
        RecordingEvidenceSink evidence = new();
        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("shell.desktop", ProvisionJobKind.ShellDesktop)]),
            Env(new FakeGuestMachine(), evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("shell.desktop", evidence.Documents[^1].Phases);
    }

    [Fact]
    public void CollectAllWingetIds_reads_every_import_package()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-desktop-import-" + Guid.NewGuid().ToString("N"));
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
                        { "PackageIdentifier": "AmN.yasb" }
                      ]
                    }
                  ]
                }
                """);

            IReadOnlyList<string> ids = ProvisioningJobRunner.CollectAllWingetIds(
                [new ProvisionJob("winget.import", ProvisionJobKind.WingetImport)],
                importPath);
            Assert.Contains("Git.Git", ids);
            Assert.Contains("AmN.yasb", ids);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
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

    private static (string GuestRoot, string YasbDir, string ThideDir) StageGuestDesktopFixture(
        bool includeKomorebi = false)
    {
        string guestRoot = Path.Combine(Path.GetTempPath(), "winmint-guest-desktop-" + Guid.NewGuid().ToString("N"));
        string native = Path.Combine(guestRoot, "yasb", "native");
        Directory.CreateDirectory(native);
        File.WriteAllText(Path.Combine(native, "config.yaml"), "screens: [\"**\"]");
        File.WriteAllText(Path.Combine(native, "styles.css"), "@import \"yasb_colors.css\";");

        if (includeKomorebi)
        {
            string komorebi = Path.Combine(guestRoot, "komorebi");
            Directory.CreateDirectory(komorebi);
            File.WriteAllText(
                Path.Combine(komorebi, "komorebi.json.template"),
                "{{WINMINT_MONITORS_JSON}} {{WINMINT_DISPLAY_INDEX_PREFERENCES_JSON}}");
            File.WriteAllText(Path.Combine(komorebi, "whkdrc"), "alt + h : komorebic focus left");
        }

        string yasbDir = Path.Combine(Path.GetTempPath(), "yasb-config-" + Guid.NewGuid().ToString("N"));
        string thideDir = Path.Combine(Path.GetTempPath(), "thide-" + Guid.NewGuid().ToString("N"));
        return (guestRoot, yasbDir, thideDir);
    }

    private static string CreateThideZip()
    {
        string zipPath = Path.Combine(Path.GetTempPath(), "thide-" + Guid.NewGuid().ToString("N") + ".zip");
        using ZipArchive archive = ZipFile.Open(zipPath, ZipArchiveMode.Create);
        ZipArchiveEntry entry = archive.CreateEntry("thide.exe");
        using Stream stream = entry.Open();
        stream.WriteByte(0x4D);
        stream.WriteByte(0x5A);
        return zipPath;
    }

    private static PathScope PrepPathWithExecutable(string fileName)
    {
        string pathDir = Path.Combine(Path.GetTempPath(), "winmint-path-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(pathDir);
        File.WriteAllText(Path.Combine(pathDir, fileName), string.Empty);
        string? oldPath = Environment.GetEnvironmentVariable("PATH");
        Environment.SetEnvironmentVariable("PATH", pathDir + Path.PathSeparator + (oldPath ?? string.Empty));
        return new PathScope(oldPath, pathDir);
    }

    private sealed class PathScope(string? oldPath, string pathDir) : IDisposable
    {
        private bool _disposed;

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            Environment.SetEnvironmentVariable("PATH", oldPath);
            if (Directory.Exists(pathDir))
            {
                Directory.Delete(pathDir, recursive: true);
            }
        }
    }
}
