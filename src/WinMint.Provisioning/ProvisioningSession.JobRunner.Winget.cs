namespace WinMint.Provisioning;

using System.Reflection.PortableExecutable;
using System.Text.Json;

public static partial class ProvisioningSession
{
    private static partial class JobRunner
    {
        private static JobsPhaseResult? RunNativePackageAuditJob(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            _ = ct;
            if (string.IsNullOrWhiteSpace(job.PackageId))
            {
                SessionStatus bad = new("jobs.failed", $"{job.Id}: audit requires packageId list.");
                env.Splash.SetStatus(bad);
                phases.Add(bad.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, bad, TimedOut: false);
            }

            List<NativePackageAuditEntry> entries = [];
            bool anyNonNative = false;
            foreach (string installId in job.PackageId.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                bool found = false;
                foreach (string path in GuessGuiBinaryPaths(installId))
                {
                    if (!File.Exists(path))
                    {
                        continue;
                    }

                    found = true;
                    bool native = IsArm64NativeBinary(path);
                    entries.Add(new NativePackageAuditEntry(installId, path, native));
                    if (!native)
                    {
                        anyNonNative = true;
                    }

                    break;
                }

                if (!found)
                {
                    entries.Add(new NativePackageAuditEntry(installId, null, null));
                }
            }

            string evidenceDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "WinMint",
                "evidence");
            Directory.CreateDirectory(evidenceDir);
            string evidencePath = Path.Combine(evidenceDir, "native-packages.json");
            NativePackageAuditDocument doc = new("winmint.native-packages/v1", entries);
            File.WriteAllText(
                evidencePath,
                JsonSerializer.Serialize(doc, NativePackageAuditJsonContext.Default.NativePackageAuditDocument));

            if (job.AuditStrict && anyNonNative)
            {
                SessionStatus failed = new(
                    "jobs.package.audit_non_native",
                    $"{job.Id}: one or more winget GUI binaries are not native ARM64 (see {evidencePath}).");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }

            return null;
        }

        private static IEnumerable<string> GuessGuiBinaryPaths(string wingetId)
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            return wingetId switch
            {
                "Anysphere.Cursor" =>
                [
                    Path.Combine(localAppData, "Programs", "cursor", "Cursor.exe"),
                    Path.Combine(localAppData, "Programs", "Cursor", "Cursor.exe"),
                ],
                "Zen-Team.Zen-Browser" =>
                [
                    Path.Combine(programFiles, "Zen Browser", "zen.exe"),
                    Path.Combine(localAppData, "Zen Browser", "zen.exe"),
                ],
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
    }
}

