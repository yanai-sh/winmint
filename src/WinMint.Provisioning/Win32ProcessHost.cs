using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
public sealed class Win32ProcessHost : IProcessHost
{
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

        if (status.Canceled)
        {
            ct.ThrowIfCancellationRequested();
            throw new OperationCanceledException("Process.RunAsync canceled.", ct);
        }

        return new ProcessStartResult(status.ExitCode);
    }
}
