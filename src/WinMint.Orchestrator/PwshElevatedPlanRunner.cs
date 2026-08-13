using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;

namespace WinMint.Orchestrator;

/// <summary>One elevated <c>pwsh -File servicing/Invoke-ServicingPlan.ps1</c> invocation per Apply (single UAC).</summary>
public sealed class PwshElevatedPlanRunner : IElevatedPlanRunner
{
    public async Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
        ServicingWorkspace workspace,
        CancellationToken ct)
    {
        string? planScript = FindServicingPlanScript();
        if (planScript is null)
        {
            return Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.plan.missing", "servicing/Invoke-ServicingPlan.ps1 not found."));
        }

        if (IsStoreMsixPwsh(ResolvePwshPath()))
        {
            return Result.Fail<ElevatedRunOk, Failure>(
                new Failure(
                    "servicing.pwsh.storeMsix",
                    "Host PowerShell is Microsoft Store MSIX; DISM/AppX offline servicing requires WinPS 5.1 or non-Store pwsh (install from GitHub)."));
        }

        if (ImageServicing.CheckSupervisorFreshness() is { } staleSupervisor)
        {
            return Result.Fail<ElevatedRunOk, Failure>(staleSupervisor);
        }

        bool elevated = IsProcessElevated();
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                planScript,
                "-WorkDirectory",
                workspace.Root,
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
                // No failure.json means the plan runner died before it could say why — a distinct
                // condition from a stage failing, and the elevated path has no stdout to fall back on.
                string? message = ReadFailureMessage(workspace);
                return Result.Fail<ElevatedRunOk, Failure>(message is null
                    ? new Failure(
                        "servicing.plan.crashed",
                        $"Invoke-ServicingPlan exited {exitCode} without writing failure.json.")
                    : new Failure("servicing.plan.failed", message));
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

    private static string? ReadFailureMessage(ServicingWorkspace workspace)
    {
        string path = workspace.Failure;
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

    internal static bool IsStoreMsixPwsh(string? processPath)
    {
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return false;
        }

        string path = processPath.Replace('/', '\\');
        return path.Contains(@"\WindowsApps\Microsoft.PowerShell", StringComparison.OrdinalIgnoreCase)
            || path.Contains(@"\WindowsApps\Microsoft.PowerShellPreview", StringComparison.OrdinalIgnoreCase);
    }

    internal static string? ResolvePwshPath()
    {
        string fileName = OperatingSystem.IsWindows() ? "pwsh.exe" : "pwsh";
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (pathEnv is null)
        {
            return null;
        }

        foreach (string dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            string candidate = Path.Combine(dir.Trim(), fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

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
