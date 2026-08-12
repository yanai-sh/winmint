namespace WinMint.Provisioning;

internal static partial class ProvisioningJobRunner
{
    private static async Task<(JobsRunResult? Failure, string? ScoopCmd)> EnsureScoopReadyAsync(
        JobContext context,
        CancellationToken ct)
    {
        JobRunnerEnv env = context.Env;
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
            JobsRunResult? fail = context.RecordPackageFailure(
                "jobs.scoop.bootstrapFailed",
                $"{context.Job.Id}: scoop bootstrap spawn: {ex.Message}",
                1);
            return (fail, null);
        }

        if (bootstrap.ExitCode != 0)
        {
            JobsRunResult? fail = context.RecordPackageFailure(
                "jobs.scoop.bootstrapFailed",
                $"{context.Job.Id}: scoop bootstrap exited {bootstrap.ExitCode} (network required).",
                bootstrap.ExitCode);
            return (fail, null);
        }

        scoopCmd = env.ResolveScoopCmd!();
        if (scoopCmd is null)
        {
            JobsRunResult? fail = context.RecordPackageFailure(
                "jobs.scoop.bootstrapFailed",
                $"{context.Job.Id}: scoop.cmd missing after bootstrap.",
                1);
            return (fail, null);
        }

        return (null, scoopCmd);
    }
}

