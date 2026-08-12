namespace WinMint.Provisioning;

using WinMint.Contracts;

internal static partial class ProvisioningJobRunner
{
    private static async Task<JobsRunResult?> RunWslPlatformJobAsync(
        JobContext context,
        CancellationToken ct)
    {
        JobRunnerEnv env = context.Env;
        ProvisionJob job = context.Job;
        bool ready = env.IsWslPlatformReady();
        if (ready)
        {
            SessionStatus skip = new("jobs.wsl.platform.ready", "WSL / Virtual Machine Platform already active.");
            env.ReportStatus(skip);
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
                return context.RequestReboot();
            }

            return FailJob(
                env,
                "jobs.failed",
                $"{job.Id}: wsl --install --no-distribution exited {started.ExitCode}.");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }

    private static void SuppressWslOobe(JobRunnerEnv env)
    {
        env.SuppressWslOobe();
    }

    private static async Task<JobsRunResult?> RunWslFromFileInstallAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(job.WslFromFileRepo)
            || job.WslFromFileAssetNames is not { Count: > 0 })
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: fromFile WSL requires repo and asset names.");
        }

        if (env.AssetDownload is null)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: fromFile WSL requires IAssetDownload.");
        }

        string? assetPath;
        try
        {
            assetPath = await env.AssetDownload.TryDownloadGitHubReleaseAssetAsync(
                    job.WslFromFileRepo,
                    job.WslFromFileAssetNames,
                    ct)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.wsl.fromFileDownloadFailed", $"{job.Id}: {ex.Message}");
        }

        if (assetPath is null)
        {
            return FailJob(
                env,
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
                    "jobs.failed",
                    $"{job.Id}: wsl --from-file exited {started.ExitCode}.");
            }

            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }
}

