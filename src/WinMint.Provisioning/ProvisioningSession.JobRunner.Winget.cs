using System.Reflection.PortableExecutable;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

using WinMint.Contracts;

namespace WinMint.Provisioning;

internal static partial class ProvisioningJobRunner
{
    private static JobsRunResult? RunNativePackageAuditJob(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        _ = ct;
        if (string.IsNullOrWhiteSpace(job.PackageId))
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: audit requires packageId list.");
        }

        List<NativePackageAuditEntryFile> entries = [];
        bool anyNonNative = false;
        foreach (string installId in job.PackageId.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            bool found = false;
            foreach (string path in GuiBinaryPaths(installId))
            {
                if (!File.Exists(path))
                {
                    continue;
                }

                found = true;
                bool native = IsArm64NativeBinary(path);
                entries.Add(new NativePackageAuditEntryFile(installId, path, native));
                if (!native)
                {
                    anyNonNative = true;
                }

                break;
            }

            if (!found)
            {
                entries.Add(new NativePackageAuditEntryFile(installId, null, null));
            }
        }

        string evidenceDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "evidence");
        Directory.CreateDirectory(evidenceDir);
        string evidencePath = Path.Combine(evidenceDir, "native-packages.json");
        NativePackageAuditFile doc = new("winmint.native-packages/v1", entries);
        File.WriteAllText(
            evidencePath,
            JsonSerializer.Serialize(doc, NativePackageAuditJsonContext.Default.NativePackageAuditFile));

        if (job.AuditStrict && anyNonNative)
        {
            return FailJob(
                env,
                "jobs.package.auditNonNative",
                $"{job.Id}: one or more winget GUI binaries are not native ARM64 (see {evidencePath}).");
        }

        return null;
    }

    internal static IEnumerable<string> GuiBinaryPaths(string wingetId)
    {
        if (wingetId.Equals(ShellChromeLayout.CursorWingetId, StringComparison.OrdinalIgnoreCase)
            || wingetId.Equals(ShellChromeLayout.ZenWingetId, StringComparison.OrdinalIgnoreCase))
        {
            return ShellChromeLayout.Candidates(wingetId);
        }

        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        return wingetId switch
        {
            "Brave.Brave" =>
            [
                Path.Combine(programFiles, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
                    Path.Combine(localAppData, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
                ],
            "Microsoft.VisualStudioCode" =>
            [
                Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe"),
                    Path.Combine(programFiles, "Microsoft VS Code", "Code.exe"),
                ],
            "ZedIndustries.Zed" =>
            [
                Path.Combine(localAppData, "Programs", "Zed", "Zed.exe"),
                    Path.Combine(programFiles, "Zed", "Zed.exe"),
                ],
            _ => [],
        };
    }

    private static bool IsArm64NativeBinary(string path)
    {
        using FileStream stream = File.OpenRead(path);
        PEReader reader = new(stream);
        return reader.PEHeaders.CoffHeader.Machine == Machine.Arm64;
    }

    internal readonly record struct WingetListedPackage(string Id, string? OverrideArguments);

    internal static bool IsCurrentProcessElevated()
    {
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    internal static IReadOnlyList<WingetListedPackage> ReadWingetImportPackages(string json)
    {
        List<WingetListedPackage> packages = [];
        using JsonDocument doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("Sources", out JsonElement sources))
        {
            return packages;
        }

        foreach (JsonElement source in sources.EnumerateArray())
        {
            if (!source.TryGetProperty("Packages", out JsonElement list))
            {
                continue;
            }

            foreach (JsonElement package in list.EnumerateArray())
            {
                if (!package.TryGetProperty("PackageIdentifier", out JsonElement idEl))
                {
                    continue;
                }

                string? id = idEl.GetString();
                if (string.IsNullOrWhiteSpace(id))
                {
                    continue;
                }

                string? arguments = null;
                if (package.TryGetProperty("InitialOverrideArguments", out JsonElement overrides)
                    && overrides.ValueKind == JsonValueKind.String)
                {
                    arguments = overrides.GetString();
                }

                packages.Add(new WingetListedPackage(id, arguments));
            }
        }

        return packages;
    }

    internal static string[] BuildWingetInstallArguments(string packageId, string? overrideArguments, string logPath)
    {
        List<string> args =
        [
            "install",
            "--id",
            packageId,
            "--exact",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity",
            "--log",
            logPath,
        ];
        if (!string.IsNullOrWhiteSpace(overrideArguments))
        {
            foreach (string part in overrideArguments.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                args.Add(part);
            }
        }

        return [.. args];
    }

    /// <summary>
    /// Zen's winget manifest is <c>Scope: machine</c>. FirstLogon is medium IL, so
    /// <c>winget install</c> elevates. Download the installer and run it into
    /// <see cref="ShellChromeLayout.ZenUserInstallDirectory"/>. Returns true only when <c>zen.exe</c> is there.
    /// ponytail: only Zen-Team.Zen-Browser. Machine-wide installs belong in machine-setup via Microsoft.WinGet.Client.
    /// </summary>
    internal static async Task<bool> TryInstallZenUserAsync(
        IProcessHost processes,
        string wingetExe,
        bool elevated,
        Action<SessionStatus> report,
        CancellationToken ct,
        string? installDirectory = null)
    {
        if (elevated)
        {
            return false;
        }

        string installDir = installDirectory ?? ShellChromeLayout.ZenUserInstallDirectory();
        string installedExe = Path.Combine(installDir, "zen.exe");
        if (File.Exists(installedExe))
        {
            return true;
        }

        try
        {
            report(new SessionStatus(
                "jobs.winget.zen.userInstall",
                "Installing Zen Browser into the user profile."));

            string downloadDir = Path.Combine(Path.GetTempPath(), "winmint-pkg-" + Guid.NewGuid().ToString("n"));
            Directory.CreateDirectory(downloadDir);
            ProcessStartResult download = await processes.RunAsync(
                wingetExe,
                [
                    "download",
                    "--id",
                    ShellChromeLayout.ZenWingetId,
                    "--exact",
                    "--architecture",
                    "arm64",
                    "--download-directory",
                    downloadDir,
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                    "--disable-interactivity",
                ],
                ct).ConfigureAwait(false);
            if (download.ExitCode != 0)
            {
                return false;
            }

            string? installer = Directory.EnumerateFiles(downloadDir, "*.exe", SearchOption.AllDirectories)
                .FirstOrDefault(path => Path.GetFileName(path).Contains("zen", StringComparison.OrdinalIgnoreCase));
            if (installer is null)
            {
                return false;
            }

            ProcessStartResult installed = await processes.RunAsync(
                installer,
                [
                    "/S",
                    "/PreventRebootRequired=true",
                    $"/InstallDirectoryPath=\"{installDir}\"",
                ],
                ct).ConfigureAwait(false);
            _ = installed;
            return File.Exists(installedExe);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _ = ex;
            return File.Exists(installedExe);
        }
    }

    private static async Task<JobsRunResult?> RunWingetImportPackagesAsync(
        JobRunnerEnv env,
        JobContext context,
        string wingetExe,
        CancellationToken ct)
    {
        string importPath = BundleLoader.DefaultGuestWingetImportPath;
        IReadOnlyList<WingetListedPackage> packages;
        try
        {
            packages = ReadWingetImportPackages(File.ReadAllText(importPath));
        }
        catch (JsonException ex)
        {
            return context.RecordPackageFailure(
                "jobs.failed",
                $"{context.Job.Id}: winget-import.json unreadable: {ex.Message}");
        }

        bool elevated = IsCurrentProcessElevated();
        bool anyFailed = false;
        foreach (WingetListedPackage package in packages)
        {
            ct.ThrowIfCancellationRequested();
            if (package.Id.Equals(ShellChromeLayout.ZenWingetId, StringComparison.OrdinalIgnoreCase)
                && await TryInstallZenUserAsync(env.Guest.Processes, wingetExe, elevated, env.ReportStatus, ct)
                    .ConfigureAwait(false))
            {
                continue;
            }

            string logPath = WingetLogPath(package.Id);
            env.ReportStatus(new SessionStatus(
                $"jobs.winget.{package.Id}.running",
                $"{package.Id} in progress…"));
            ProcessStartResult started = await env.Guest.Processes.RunAsync(
                wingetExe,
                BuildWingetInstallArguments(package.Id, package.OverrideArguments, logPath),
                ct).ConfigureAwait(false);
            if (started.ExitCode == 0)
            {
                continue;
            }

            anyFailed = true;
            string? tail = TryReadLogTail(logPath);
            string message = string.IsNullOrWhiteSpace(tail)
                ? $"{package.Id} exited {started.ExitCode}."
                : $"{package.Id} exited {started.ExitCode}. {tail}";
            JobsRunResult? failed = context.RecordNamedPackageFailure(package.Id, started.ExitCode, message);
            if (failed is not null)
            {
                return failed;
            }
        }

        if (!anyFailed && context.Job.NeedsReboot)
        {
            return context.RequestReboot();
        }

        return null;
    }

    private static string WingetLogPath(string packageId)
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "evidence");
        Directory.CreateDirectory(dir);
        string safe = string.Concat(packageId.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        return Path.Combine(dir, $"winget-{safe}.log");
    }

    internal static string? TryReadLogTail(string path, int maxChars = 1200)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        using StreamReader reader = new(path, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        string text = reader.ReadToEnd().Trim();
        if (text.Length == 0)
        {
            return null;
        }

        return text.Length <= maxChars ? text : text[^maxChars..];
    }
}

