namespace WinMint.Provisioning;

using WinMint.Contracts;

public static partial class ProvisioningSession
{
    private static partial class JobRunner
    {
        private static async Task<(JobsPhaseResult? Failure, string? ScoopCmd)> EnsureScoopReadyAsync(
            ShellEnvironment env,
            ProvisionJob job,
            Func<ProvisionJob, string, string, int, JobsPhaseResult?> recordFailure,
            CancellationToken ct)
        {
            string? scoopCmd = env.ResolveScoopCmd!();
            if (scoopCmd is not null)
            {
                return (null, scoopCmd);
            }

            ProcessStartResult bootstrap;
            try
            {
                bootstrap = await env.Processes.RunAsync(
                        "powershell.exe",
                        [
                            "-NoProfile",
                            "-ExecutionPolicy",
                            "Bypass",
                            "-Command",
                            """iex "& {$(irm get.scoop.sh)} -RunAsAdmin"; exit $LASTEXITCODE""",
                        ],
                        ct)
                    .ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrapFailed",
                    $"{job.Id}: scoop bootstrap spawn: {ex.Message}",
                    1);
                return (fail, null);
            }

            if (bootstrap.ExitCode != 0)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrapFailed",
                    $"{job.Id}: scoop bootstrap exited {bootstrap.ExitCode} (network required).",
                    bootstrap.ExitCode);
                return (fail, null);
            }

            scoopCmd = env.ResolveScoopCmd!();
            if (scoopCmd is null)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrapFailed",
                    $"{job.Id}: scoop.cmd missing after bootstrap.",
                    1);
                return (fail, null);
            }

            return (null, scoopCmd);
        }
    }
}

