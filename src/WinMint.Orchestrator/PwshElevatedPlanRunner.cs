using System.Collections.Frozen;
using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>One elevated <c>pwsh -File servicing/RunPlan.ps1</c> invocation per Apply (single UAC).</summary>
public sealed class PwshElevatedPlanRunner : IElevatedPlanRunner
{
    public async Task<Result<ImageEvidence, Failure>> ExecuteAsync(
        string workDirectory,
        IReadOnlyList<ServicingStage> stages,
        ServicingRun run,
        BuildArtifacts plan,
        CancellationToken ct)
    {
        string? runPlan = FindRunPlanScript();
        if (runPlan is null)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.runPlan.missing", "servicing/RunPlan.ps1 not found."));
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
                runPlan,
                "-WorkDirectory",
                workDirectory,
            },
            WorkingDirectory = Path.GetDirectoryName(runPlan)!,
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
                return Result.Fail<ImageEvidence, Failure>(
                    new Failure("servicing.cancelled", "Apply was cancelled."));
            }

            if (exitCode != 0)
            {
                string message = ReadFailureMessage(workDirectory) ?? $"RunPlan exited {exitCode}.";
                return Result.Fail<ImageEvidence, Failure>(
                    new Failure("servicing.runPlan.failed", message));
            }
        }
        catch (OperationCanceledException)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.cancelled", "Apply was cancelled."));
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.elevation.failed", ex.Message));
        }

        return ReadEvidence(workDirectory, plan, run, stages);
    }

    private static Result<ImageEvidence, Failure> ReadEvidence(
        string workDirectory,
        BuildArtifacts plan,
        ServicingRun run,
        IReadOnlyList<ServicingStage> stages)
    {
        string evidencePath = Path.Combine(workDirectory, "evidence.json");
        if (!File.Exists(evidencePath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.missing", "RunPlan succeeded but evidence.json is missing."));
        }

        EvidenceFile? file;
        try
        {
            file = JsonSerializer.Deserialize(
                File.ReadAllBytes(evidencePath),
                ServicingJsonContext.Default.EvidenceFile);
        }
        catch (JsonException ex)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.invalid", ex.Message));
        }

        if (file is null
            || !string.Equals(file.SchemaVersion, ImageServicing.EvidenceSchemaVersion, StringComparison.Ordinal))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.schema",
                    $"Expected {ImageServicing.EvidenceSchemaVersion}."));
        }

        ServicingStage? stamp = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.StampOfflineShell);
        if (stamp is null
            || !stamp.Parameters.TryGetValue(StageParams.ShellTarget, out string? shellTarget)
            || string.IsNullOrWhiteSpace(shellTarget))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.shellStamp.missing",
                    "StampOfflineShell stage missing or incomplete."));
        }

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                file.OutputIsoPath
                    ?? run.OutputIsoPath
                    ?? OutputIsoNaming.DefaultPath(workDirectory, profilePath: null, plan.Manifest.ImageQuality),
                plan.Manifest.ImageQuality,
                file.ShellStampTargetPath ?? shellTarget,
                file.Digests?.ToFrozenDictionary(StringComparer.Ordinal)
                    ?? (IReadOnlyDictionary<string, string>)FrozenDictionary<string, string>.Empty));
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

    private static string? FindRunPlanScript()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            string candidate = Path.Combine(dir, "servicing", "RunPlan.ps1");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            DirectoryInfo? parent = Directory.GetParent(dir);
            if (parent is null)
            {
                break;
            }

            dir = parent.FullName;
        }

        string cwd = Path.Combine(Directory.GetCurrentDirectory(), "servicing", "RunPlan.ps1");
        return File.Exists(cwd) ? cwd : null;
    }

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

internal sealed record EvidenceFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("outputIsoPath")] string? OutputIsoPath,
    [property: JsonPropertyName("shellStampTargetPath")] string? ShellStampTargetPath,
    [property: JsonPropertyName("lane")] string? Lane,
    [property: JsonPropertyName("packageStrict")] bool PackageStrict,
    [property: JsonPropertyName("digests")] Dictionary<string, string>? Digests);

internal sealed record FailureFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("message")] string? Message,
    [property: JsonPropertyName("opcode")] string? Opcode);
