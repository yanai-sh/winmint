using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;

namespace WinMint.Orchestrator;

/// <summary>One elevated <c>pwsh -File servicing/Invoke-ServicingPlan.ps1</c> invocation per Apply (single UAC).</summary>
public sealed class PwshElevatedPlanRunner : IElevatedPlanRunner
{
    public async Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
        string workDirectory,
        CancellationToken ct)
    {
        string? planScript = FindServicingPlanScript();
        if (planScript is null)
        {
            return Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.plan.missing", "servicing/Invoke-ServicingPlan.ps1 not found."));
        }

        string pwsh = ResolvePwsh();
        bool elevated = IsProcessElevated();
        ProcessStartInfo psi = new()
        {
            FileName = pwsh,
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                planScript,
                "-WorkDirectory",
                workDirectory,
            },
            WorkingDirectory = Path.GetDirectoryName(planScript)!,
            UseShellExecute = !elevated,
        };
        if (!elevated)
        {
            // UAC Verb=runas requires UseShellExecute; Process.Run / RunAsync reject UseShellExecute.
            psi.Verb = "runas";
        }

        try
        {
            ct.ThrowIfCancellationRequested();

            int exitCode;
            if (elevated)
            {
                // Already elevated: Process.RunAsync honors CancellationToken (kills child on cancel).
                // Process.Run / RunAsync reject UseShellExecute — elevated path only.
                ProcessExitStatus status = await Process.RunAsync(psi, ct).ConfigureAwait(false);
                exitCode = status.ExitCode;
            }
            else
            {
                // UAC Verb=runas requires UseShellExecute — Process.Run rejects that, so Start + WaitForExit.
                // ct.Register kills the child on cancel (WaitForExit itself is not cancelable).
                using Process process = Process.Start(psi)
                    ?? throw new InvalidOperationException("Failed to start elevated pwsh.");
                using (ct.Register(() =>
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            process.Kill(entireProcessTree: true);
                        }
                    }
                    catch
                    {
                        // ponytail: best-effort cancel of elevated child
                    }
                }))
                {
                    process.WaitForExit();
                }

                exitCode = process.ExitCode;
            }

            if (ct.IsCancellationRequested)
            {
                return Result.Fail<ElevatedRunOk, Failure>(
                    new Failure("servicing.cancelled", "Apply was cancelled."));
            }

            if (exitCode != 0)
            {
                string message = ReadFailureMessage(workDirectory) ?? $"Invoke-ServicingPlan exited {exitCode}.";
                return Result.Fail<ElevatedRunOk, Failure>(
                    new Failure("servicing.plan.failed", message));
            }
        }
        catch (OperationCanceledException)
        {
            return Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.cancelled", "Apply was cancelled."));
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            return Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.elevation.failed", ex.Message));
        }

        return Result.Ok<ElevatedRunOk, Failure>(default);
    }

    private static string? ReadFailureMessage(string workDirectory)
    {
        string path = Path.Combine(workDirectory, "failure.json");
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            FailureFile? failure = JsonSerializer.Deserialize(
                File.ReadAllBytes(path),
                ServicingJsonContext.Default.FailureFile);
            return failure?.Message;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? FindServicingPlanScript() => ToolkitRoot.TryFind("servicing", "Invoke-ServicingPlan.ps1");

    private static string ResolvePwsh() => "pwsh";

    private static bool IsProcessElevated()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }
}
