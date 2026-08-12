namespace WinMint.Provisioning;

using WinMint.Contracts;

using System.Net.Http.Json;

public static partial class ProvisioningSession
{
    private static partial class JobRunner
    {
        private static async Task<JobsPhaseResult?> RunWslPlatformJobAsync(
            ShellEnvironment env,
            List<string> phases,
            ProvisionJob job,
            int jobIndex,
            CancellationToken ct)
        {
            bool ready = env.IsWslPlatformReady?.Invoke()
                ?? (OperatingSystem.IsWindows() && Win32WslPlatform.IsVirtualMachinePlatformReady());
            if (ready)
            {
                SessionStatus skip = new("jobs.wsl.platform.ready", "WSL / Virtual Machine Platform already active.");
                Note(env, phases, skip);
                return null;
            }

            try
            {
                ProcessStartResult started = await env.Processes.RunAsync(
                        "wsl.exe",
                        ["--install", "--no-distribution"],
                        ct)
                    .ConfigureAwait(false);

                // 0 = enabled (reboot still required for VMP); 3010/1641 = explicit reboot-needed.
                if (started.ExitCode is 0
                    || Win32WslPlatform.IsRebootRequiredExitCode(started.ExitCode))
                {
                    return RequestJobReboot(env, phases, job, jobIndex + 1);
                }

                return FailJob(
                    env,
                    phases,
                    "jobs.failed",
                    $"{job.Id}: wsl --install --no-distribution exited {started.ExitCode}.");
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                return FailJob(env, phases, "jobs.failed", $"{job.Id}: {ex.Message}");
            }
        }

        private static void SuppressWslOobe(ShellEnvironment env)
        {
            if (env.SuppressWslOobe is not null)
            {
                env.SuppressWslOobe();
                return;
            }

            if (OperatingSystem.IsWindows())
            {
                Win32WslPlatform.SuppressDistroOobe();
            }
        }

        private static async Task<JobsPhaseResult?> RunWslFromFileInstallAsync(
            ShellEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            if (string.IsNullOrWhiteSpace(job.WslFromFileRepo)
                || job.WslFromFileAssetNames is not { Count: > 0 })
            {
                return FailJob(env, phases, "jobs.failed", $"{job.Id}: fromFile WSL requires repo and asset names.");
            }

            string? assetPath;
            try
            {
                assetPath = await DownloadWslFromFileAssetAsync(job.WslFromFileRepo, job.WslFromFileAssetNames, ct)
                    .ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                return FailJob(env, phases, "jobs.wsl.fromFileDownloadFailed", $"{job.Id}: {ex.Message}");
            }

            if (assetPath is null)
            {
                return FailJob(
                    env,
                    phases,
                    "jobs.wsl.fromFileAssetMissing",
                    $"{job.Id}: no matching GitHub release asset for {job.WslFromFileRepo}.");
            }

            try
            {
                ProcessStartResult started = await env.Processes.RunAsync(
                        "wsl.exe",
                        ["--install", "--from-file", assetPath, "--no-launch"],
                        ct)
                    .ConfigureAwait(false);
                if (started.ExitCode != 0)
                {
                    return FailJob(
                        env,
                        phases,
                        "jobs.failed",
                        $"{job.Id}: wsl --from-file exited {started.ExitCode}.");
                }

                return null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                return FailJob(env, phases, "jobs.failed", $"{job.Id}: {ex.Message}");
            }
        }

        private static async Task<string?> DownloadWslFromFileAssetAsync(
            string repo,
            IReadOnlyList<string> assetNameHints,
            CancellationToken ct)
        {
            using HttpClient client = new();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("WinMint-Provisioning/1.0");
            string url = $"https://api.github.com/repos/{repo}/releases/latest";
            using HttpResponseMessage response = await client.GetAsync(url, ct).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            GitHubRelease? release = await response.Content.ReadFromJsonAsync(
                GitHubReleaseJsonContext.Default.GitHubRelease,
                ct).ConfigureAwait(false);
            if (release?.Assets is null)
            {
                return null;
            }

            foreach (string hint in assetNameHints)
            {
                GitHubAsset? asset = release.Assets.FirstOrDefault(
                    a => a.Name.Contains(hint, StringComparison.OrdinalIgnoreCase));
                if (asset?.BrowserDownloadUrl is null)
                {
                    continue;
                }

                string tempDir = Path.Combine(Path.GetTempPath(), "WinMint", "wsl");
                Directory.CreateDirectory(tempDir);
                string dest = Path.Combine(tempDir, asset.Name);
                using HttpResponseMessage assetResponse = await client.GetAsync(asset.BrowserDownloadUrl, ct)
                    .ConfigureAwait(false);
                assetResponse.EnsureSuccessStatusCode();
                await using FileStream stream = File.Create(dest);
                await assetResponse.Content.CopyToAsync(stream, ct).ConfigureAwait(false);
                return dest;
            }

            return null;
        }
    }
}

