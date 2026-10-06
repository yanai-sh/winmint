using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;

namespace WinMint.Orchestrator;

/// <summary>One elevated <c>pwsh -File servicing/Invoke-ServicingPlan.ps1</c> invocation per Apply (single UAC).</summary>
public sealed class PwshElevatedPlanRunner(Action<string>? onProgress = null) : IElevatedPlanRunner
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

        string? pwshPath = ResolvePwshPath();
        if (RefuseStoreMsixPwsh(pwshPath) is { } storeMsix)
        {
            return Result.Fail<ElevatedRunOk, Failure>(storeMsix);
        }

        if (ImageServicing.CheckSupervisorFreshness() is { } staleSupervisor)
        {
            return Result.Fail<ElevatedRunOk, Failure>(staleSupervisor);
        }

        if (ImageServicing.CheckWinPeApplyFreshness() is { } staleWinPeApply)
        {
            return Result.Fail<ElevatedRunOk, Failure>(staleWinPeApply);
        }

        bool elevated = IsProcessElevated();
        ProcessStartInfo psi = new()
        {
            FileName = pwshPath,
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
                // Process.Run / RunAsync reject UseShellExecute — elevated path only. No parent poll
                // (child shares console / Write-WinMintHostPhase).
                ProcessExitStatus status = await Process.RunAsync(psi, ct).ConfigureAwait(false);
                exitCode = status.ExitCode;
            }
            else
            {
                // UAC Verb=runas requires UseShellExecute — Process.Run rejects that, so Start + wait loop.
                // ct.Register kills the child on cancel (WaitForExit(timeout) is cancelable via Kill).
                onProgress?.Invoke(
                    $"Applying… work={workspace.Root} (just watch-apply for log tail)");
                ApplyOperatorProgressTracker tracker = new();
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
                    while (!process.WaitForExit(1000))
                    {
                        EmitProgress(workspace, tracker, onProgress, ct.IsCancellationRequested);
                        if (ct.IsCancellationRequested)
                        {
                            break;
                        }
                    }
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
                return Result.Fail<ElevatedRunOk, Failure>(BuildPlanFailure(workspace, exitCode));
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

    private static void EmitProgress(
        ServicingWorkspace workspace,
        ApplyOperatorProgressTracker tracker,
        Action<string>? onProgress,
        bool cancelled)
    {
        if (onProgress is null || cancelled)
        {
            return;
        }

        ApplyProgress? snap = workspace.TryReadProgress();
        long? logLength = ApplyOperatorProgressTracker.TryGetLogLength(snap?.LogPath);
        string? line = tracker.Consider(snap, logLength, cancelled);
        if (line is not null)
        {
            onProgress(line);
        }
    }

    private static Failure BuildPlanFailure(ServicingWorkspace workspace, int exitCode)
    {
        ApplyProgress? progress = workspace.TryReadProgress();
        string? stage = progress?.Stage;
        string? logPath = progress?.LogPath;

        if (!TryReadFailureFile(workspace, out string? opcode, out string? message))
        {
            return new Failure(
                "servicing.plan.crashed",
                ApplyOperatorMessages.FormatCrashed(workspace.Root, exitCode));
        }

        return new Failure(
            "servicing.plan.failed",
            ApplyOperatorMessages.FormatFailed(workspace.Root, opcode, message, stage, logPath));
    }

    private static bool TryReadFailureFile(
        ServicingWorkspace workspace,
        out string? opcode,
        out string? message)
    {
        opcode = null;
        message = null;
        string path = workspace.Failure;
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            FailureFile? failure = JsonSerializer.Deserialize(
                File.ReadAllBytes(path),
                ServicingJsonContext.Default.FailureFile);
            if (failure is null)
            {
                return false;
            }

            opcode = failure.Opcode;
            message = failure.Message;
            return !string.IsNullOrWhiteSpace(message) || !string.IsNullOrWhiteSpace(opcode);
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string? FindServicingPlanScript() => ToolkitRoot.TryFind("servicing", "Invoke-ServicingPlan.ps1");

    internal static Failure? RefuseStoreMsixPwsh(string? pwshPath)
    {
        if (pwshPath is null || IsStoreMsixPwsh(pwshPath))
        {
            return new Failure(
                "servicing.pwsh.storeMsix",
                "Host pwsh is WindowsApps MSIX (winget Microsoft.PowerShell defaults to msix). DISM needs GitHub PowerShell-*-win-arm64.msi (or win-x64) under Program Files\\PowerShell\\7.");
        }

        return null;
    }

    internal static bool IsStoreMsixPwsh(string? processPath)
    {
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return false;
        }

        string path = processPath.Replace('/', '\\');
        // Packaged install (GitHub MSIX or Store) and the WindowsApps execution alias both run DISM as MSIX.
        return path.Contains(@"\WindowsApps\", StringComparison.OrdinalIgnoreCase);
    }

    internal static string? FirstNonStorePwsh(params string[] existingPaths)
    {
        foreach (string path in existingPaths)
        {
            if (!string.IsNullOrWhiteSpace(path) && !IsStoreMsixPwsh(path))
            {
                return path;
            }
        }

        return null;
    }

    internal static string? ResolvePwshPath()
    {
        string fileName = OperatingSystem.IsWindows() ? "pwsh.exe" : "pwsh";
        List<string> candidates = [];
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (pathEnv is not null)
        {
            foreach (string dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            {
                candidates.Add(Path.Combine(dir.Trim(), fileName));
            }
        }

        if (OperatingSystem.IsWindows())
        {
            candidates.Add(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "PowerShell",
                "7",
                fileName));
        }

        IEnumerable<string> existing = candidates.Where(File.Exists);
        return FirstNonStorePwsh([.. existing]);
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
