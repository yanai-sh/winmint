using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
public sealed class Win32ProcessHost : IProcessHost
{
    public ProcessStartResult Run(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        ArgumentNullException.ThrowIfNull(arguments);

        // Sync Process.Run has timeout but no mid-flight CancellationToken (RunAsync does).
        // Check before start only — JobRunner and other cancel-sensitive callers use RunAsync.
        ct.ThrowIfCancellationRequested();

        ProcessExitStatus status = Process.Run(
            fileName,
            [.. arguments],
            silent: true,
            timeout: null);

        return new ProcessStartResult(status.ExitCode);
    }

    public async Task<ProcessStartResult> RunAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        ArgumentNullException.ThrowIfNull(arguments);

        ProcessExitStatus status = await Process.RunAsync(
                fileName,
                [.. arguments],
                silent: true,
                cancellationToken: ct)
            .ConfigureAwait(false);

        return new ProcessStartResult(status.ExitCode);
    }
}
