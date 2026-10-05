using WinMint.Contracts;

namespace WinMint.Provisioning;

internal static partial class ProvisioningJobRunner
{
    private static async Task<JobsRunResult?> RunWslPlatformJobAsync(
        JobContext context,
        IReadOnlyList<string> remainingDistros,
        CancellationToken ct)
    {
        JobRunnerEnv env = context.Env;
        ProvisionJob job = context.Job;
        if (env.Guest.IsHypervisorGuest())
        {
            env.WslMock.Mocked = true;
            env.ReportStatus(new SessionStatus(
                "jobs.wsl.platform.mocked",
                "WSL mocked on hypervisor guest."));
            try
            {
                env.Guest.TryStageWslTerminalMock(remainingDistros);
            }
            catch
            {
                // Best-effort Terminal mock — hypervisor skip must still succeed.
            }

            return null;
        }

        bool ready = env.Guest.IsWslPlatformReady();
        if (ready)
        {
            SessionStatus skip = new("jobs.wsl.platform.ready", "WSL / Virtual Machine Platform already active.");
            env.ReportStatus(skip);
            return null;
        }

        try
        {
            ProcessStartResult started = await env.Guest.Processes.RunAsync(
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
        env.Guest.SuppressWslOobe();
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

        if (env.Guest.AssetDownload is null)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: fromFile WSL requires IAssetDownload.");
        }

        string? assetPath;
        try
        {
            assetPath = await env.Guest.AssetDownload.TryDownloadGitHubReleaseAssetAsync(
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
            ProcessStartResult started = await env.Guest.Processes.RunAsync(
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

