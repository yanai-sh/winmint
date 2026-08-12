using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace WinMint.Orchestrator;

public sealed record PackagesProofRefreshResult(string ProofPath, int EntryCount);

public static partial class PackagesProof
{
    internal const string RequestSchemaVersion = "winmint.packages.check.request/v1";
    internal const string OutcomeSchemaVersion = "winmint.packages.check.outcome/v1";

    /// <summary>
    /// Proves the shipped ARM64 package catalog through one native PowerShell invocation and
    /// atomically replaces <c>config/packages.proof.json</c> only after exact reconciliation.
    /// </summary>
    public static async Task<Result<PackagesProofRefreshResult, Failure>> RefreshAsync(
        string toolkitRoot,
        CancellationToken ct = default)
    {
        string root = Path.GetFullPath(toolkitRoot);
        string catalogPath = Path.Combine(root, "config", "packages.json");
        string proofPath = Path.Combine(root, "config", "packages.proof.json");
        string scriptPath = Path.Combine(root, "tools", "host", "Invoke-PackagesCheck.ps1");

        Result<PackageCatalog, Failure> loaded = PackageCatalog.TryLoadFromFile(catalogPath);
        if (!loaded.IsOk)
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(loaded.Error);
        }

        IReadOnlyList<string> catalogErrors = loaded.Value.Validate();
        if (catalogErrors.Count > 0)
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(
                new Failure("packages.proof.catalogInvalid", string.Join(Environment.NewLine, catalogErrors)));
        }

        IReadOnlyList<PackagesProofEntry> proveSet =
            BuildProveSet(loaded.Value, DefaultArchitecture);
        IReadOnlyList<string> duplicates = DuplicateIdentities(proveSet);
        if (duplicates.Count > 0)
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(
                new Failure(
                    "packages.proof.duplicateIdentity",
                    $"Catalog prove set contains duplicate identities: {string.Join(", ", duplicates)}"));
        }

        IReadOnlyList<string> missingConstants = MissingProductConstants(loaded.Value);
        if (missingConstants.Count > 0)
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(
                new Failure(
                    "packages.proof.productConstants",
                    $"Product constants are missing or stubbed: {string.Join(", ", missingConstants)}"));
        }

        if (!File.Exists(scriptPath))
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(
                new Failure("packages.proof.scriptMissing", $"Packages check script not found: {scriptPath}"));
        }

        Architecture osArchitecture = RuntimeInformation.OSArchitecture;
        Architecture processArchitecture = RuntimeInformation.ProcessArchitecture;
        if (osArchitecture is not Architecture.Arm64 || processArchitecture is not Architecture.Arm64)
        {
            return Result.Fail<PackagesProofRefreshResult, Failure>(
                new Failure(
                    "packages.proof.nativeArm64Required",
                    "packages-check requires native ARM64 "
                    + $"(OSArchitecture={osArchitecture}, ProcessArchitecture={processArchitecture}, "
                    + $"PROCESSOR_ARCHITECTURE={Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") ?? "<unset>"}, "
                    + $"PROCESSOR_ARCHITEW6432={Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432") ?? "<unset>"})."));
        }

        PackagesCheckRequestFile request = new()
        {
            SchemaVersion = RequestSchemaVersion,
            Architecture = DefaultArchitecture,
            CatalogSha256 = CatalogSha256(catalogPath),
            Entries = proveSet
                .Select(e => new PackagesCheckEntryFile
                {
                    Source = e.Source,
                    Id = e.Id,
                    Bucket = e.ScoopBucket,
                })
                .ToList(),
        };

        string runDirectory = Path.Combine(
            root,
            ".scratch",
            "packages-check",
            Guid.NewGuid().ToString("N"));
        string requestPath = Path.Combine(runDirectory, "request.json");
        string outcomePath = Path.Combine(runDirectory, "outcome.json");

        try
        {
            Directory.CreateDirectory(runDirectory);
            WriteJsonAtomically(
                requestPath,
                request,
                PackagesProofJsonContext.Default.PackagesCheckRequestFile);

            ProcessStartInfo startInfo = new()
            {
                FileName = "pwsh",
                WorkingDirectory = root,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                ArgumentList =
                {
                    "-NoProfile",
                    "-File",
                    scriptPath,
                    "-RequestPath",
                    requestPath,
                    "-OutcomePath",
                    outcomePath,
                },
            };

            using Process process = new() { StartInfo = startInfo };
            if (!process.Start())
            {
                return Failed("packages.proof.processStart", "Failed to start native pwsh.", runDirectory);
            }

            Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync(ct);
            Task<string> stderrTask = process.StandardError.ReadToEndAsync(ct);
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
                    // ponytail: cancellation already won; process cleanup is best effort
                }
            }))
            {
                await process.WaitForExitAsync(ct).ConfigureAwait(false);
            }
            string stdout = await stdoutTask.ConfigureAwait(false);
            string stderr = await stderrTask.ConfigureAwait(false);

            if (!File.Exists(outcomePath))
            {
                return Failed(
                    "packages.proof.outcomeMissing",
                    $"Packages check exited {process.ExitCode} without an outcome. {ProcessDetail(stdout, stderr)}",
                    runDirectory);
            }

            PackagesCheckOutcomeFile? outcome;
            try
            {
                outcome = JsonSerializer.Deserialize(
                    File.ReadAllBytes(outcomePath),
                    PackagesProofJsonContext.Default.PackagesCheckOutcomeFile);
            }
            catch (JsonException ex)
            {
                return Failed("packages.proof.outcomeInvalid", ex.Message, runDirectory);
            }

            Result<PackagesProofFile, Failure> reconciled = Reconcile(request, outcome, process.ExitCode);
            if (!reconciled.IsOk)
            {
                return Failed(
                    reconciled.Error.Code,
                    $"{reconciled.Error.Message} {ProcessDetail(stdout, stderr)}",
                    runDirectory);
            }

            File.WriteAllText(Path.Combine(runDirectory, "stdout.txt"), stdout);
            File.WriteAllText(Path.Combine(runDirectory, "stderr.txt"), stderr);
            Result<PackagesProofFile, Failure> replaced = ReplaceProofAfterScratchCleanup(
                proofPath,
                runDirectory,
                reconciled.Value);
            if (!replaced.IsOk)
            {
                bool preserved = PreserveRunDiagnostics(
                    runDirectory,
                    request,
                    outcome!,
                    stdout,
                    stderr);
                return Failed(
                    replaced.Error.Code,
                    replaced.Error.Message,
                    runDirectory,
                    preserved);
            }

            return Result.Ok<PackagesProofRefreshResult, Failure>(
                new PackagesProofRefreshResult(proofPath, request.Entries.Count));
        }
        catch (OperationCanceledException)
        {
            return Failed("packages.proof.cancelled", "Packages check was cancelled.", runDirectory);
        }
        catch (Exception ex) when (
            ex is IOException
                or UnauthorizedAccessException
                or System.ComponentModel.Win32Exception
                or InvalidOperationException)
        {
            return Failed("packages.proof.refreshFailed", ex.Message, runDirectory);
        }
    }

    internal static Result<PackagesProofFile, Failure> Reconcile(
        PackagesCheckRequestFile request,
        PackagesCheckOutcomeFile? outcome,
        int processExitCode)
    {
        if (outcome is null)
        {
            return ReconcileFailure("Outcome JSON deserialized to null.");
        }

        if (!string.IsNullOrEmpty(outcome.FatalError))
        {
            return ReconcileFailure($"Packages check reported a fatal error: {outcome.FatalError}");
        }

        if (processExitCode != 0)
        {
            return ReconcileFailure($"Packages check process exited {processExitCode}.");
        }

        IReadOnlyList<string> requestDuplicates = DuplicateIdentities(
            request.Entries.Select(
                entry => new PackagesProofEntry(
                    entry.Source ?? "",
                    entry.Id ?? "",
                    entry.Bucket)));
        if (requestDuplicates.Count > 0)
        {
            return ReconcileFailure(
                $"Request contains duplicate identities: {string.Join(", ", requestDuplicates)}.");
        }

        if (!string.Equals(outcome.SchemaVersion, OutcomeSchemaVersion, StringComparison.Ordinal))
        {
            return ReconcileFailure($"Outcome schemaVersion must be {OutcomeSchemaVersion}.");
        }

        if (!string.Equals(outcome.Architecture, request.Architecture, StringComparison.Ordinal)
            || !string.Equals(outcome.CatalogSha256, request.CatalogSha256, StringComparison.Ordinal))
        {
            return ReconcileFailure("Outcome identity does not match the request.");
        }

        PackagesCheckHostFile? host = outcome.Host;
        if (host is null
            || !string.Equals(host.OsArchitecture, "Arm64", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(host.ProcessArchitecture, "Arm64", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(host.ProcessorArchitecture, "ARM64", StringComparison.OrdinalIgnoreCase)
            || !host.ProcessorArchitectureW6432Present
            || (!string.IsNullOrWhiteSpace(host.ProcessorArchitectureW6432)
                && !string.Equals(
                    host.ProcessorArchitectureW6432,
                    "ARM64",
                    StringComparison.OrdinalIgnoreCase))
            || string.IsNullOrWhiteSpace(host.WingetVersion))
        {
            return ReconcileFailure(
                "Outcome host diagnostics are missing or do not prove a native ARM64 host with winget.");
        }

        if (outcome.CompletedAtUtc is null
            || outcome.CompletedAtUtc == default
            || outcome.CompletedAtUtc.Value.Offset != TimeSpan.Zero)
        {
            return ReconcileFailure("Outcome completedAtUtc must be a valid UTC timestamp.");
        }

        List<PackagesCheckResultFile?> results = outcome.Results ?? [];
        if (results.Count != request.Entries.Count)
        {
            return ReconcileFailure(
                $"Outcome result count must be exactly {request.Entries.Count} (got {results.Count}).");
        }

        List<PackagesProofEntryFile?> proofEntries = new(request.Entries.Count);
        for (int i = 0; i < request.Entries.Count; i++)
        {
            PackagesCheckEntryFile expected = request.Entries[i];
            PackagesCheckResultFile? actual = results[i];
            if (actual is null
                || string.IsNullOrWhiteSpace(actual.Source)
                || string.IsNullOrWhiteSpace(actual.Id))
            {
                return ReconcileFailure($"Outcome result {i} is malformed.");
            }

            if (!string.Equals(actual.Source, expected.Source, StringComparison.Ordinal)
                || !string.Equals(actual.Id, expected.Id, StringComparison.Ordinal)
                || !string.Equals(actual.Bucket, expected.Bucket, StringComparison.Ordinal))
            {
                return ReconcileFailure($"Outcome result {i} identity or bucket does not match the request.");
            }

            string method = ExpectedMethod(expected.Source!);
            if (!string.Equals(actual.Method, method, StringComparison.Ordinal))
            {
                return ReconcileFailure($"Outcome result {i} method must be {method}.");
            }

            if (!actual.Succeeded)
            {
                return ReconcileFailure(
                    $"Package target {actual.Source}:{actual.Id} failed: {actual.Error ?? "unknown error"}");
            }

            if (!string.IsNullOrEmpty(actual.Error))
            {
                return ReconcileFailure(
                    $"Successful outcome result {actual.Source}:{actual.Id} must not contain an error.");
            }

            proofEntries.Add(new PackagesProofEntryFile
            {
                Source = expected.Source,
                Id = expected.Id,
                Bucket = expected.Bucket,
                Method = actual.Method,
            });
        }

        return Result.Ok<PackagesProofFile, Failure>(new PackagesProofFile
        {
            SchemaVersion = SchemaVersion,
            Architecture = request.Architecture,
            CatalogSha256 = request.CatalogSha256,
            ProveSetSha256 = ProveSetSha256(
                request.Entries.Select(
                    e => new PackagesProofEntry(e.Source!, e.Id!, e.Bucket)).ToArray()),
            ProvenAtUtc = outcome.CompletedAtUtc,
            Host = new PackagesProofHostFile
            {
                OsArchitecture = host.OsArchitecture,
                ProcessArchitecture = host.ProcessArchitecture,
                ProcessorArchitecture = host.ProcessorArchitecture,
                ProcessorArchitectureW6432 = host.ProcessorArchitectureW6432,
                WingetVersion = host.WingetVersion,
            },
            Entries = proofEntries,
        });
    }

    private static Result<PackagesProofFile, Failure> ReconcileFailure(string message) =>
        Result.Fail<PackagesProofFile, Failure>(
            new Failure("packages.proof.outcomeMismatch", message));

    private static Result<PackagesProofRefreshResult, Failure> Failed(
        string code,
        string message,
        string runDirectory,
        bool runDirectoryPreserved = true) =>
        Result.Fail<PackagesProofRefreshResult, Failure>(
            new Failure(
                code,
                runDirectoryPreserved
                    ? $"{message} Run directory preserved: {runDirectory}"
                    : $"{message} Failed to recreate run diagnostics at: {runDirectory}"));

    private static string ProcessDetail(string stdout, string stderr)
    {
        string detail = string.Join(
            Environment.NewLine,
            new[] { stdout.Trim(), stderr.Trim() }.Where(s => s.Length > 0));
        if (detail.Length == 0)
        {
            return "";
        }

        const int maxLength = 1200;
        return detail.Length <= maxLength ? detail : detail[^maxLength..];
    }

    internal static Result<PackagesProofFile, Failure> ReplaceProofAfterScratchCleanup(
        string proofPath,
        string runDirectory,
        PackagesProofFile proof)
    {
        string stagedProofPath;
        try
        {
            stagedProofPath = StageJson(
                proofPath,
                proof,
                PackagesProofJsonContext.Default.PackagesProofFile);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Result.Fail<PackagesProofFile, Failure>(
                new Failure("packages.proof.stageFailed", ex.Message));
        }

        try
        {
            Directory.Delete(runDirectory, recursive: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            File.Delete(stagedProofPath);
            return Result.Fail<PackagesProofFile, Failure>(
                new Failure(
                    "packages.proof.scratchCleanupFailed",
                    $"Could not remove successful run directory: {ex.Message}"));
        }

        try
        {
            CommitStagedJson(stagedProofPath, proofPath);
            return Result.Ok<PackagesProofFile, Failure>(proof);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Result.Fail<PackagesProofFile, Failure>(
                new Failure("packages.proof.replaceFailed", ex.Message));
        }
        finally
        {
            File.Delete(stagedProofPath);
        }
    }

    private static bool PreserveRunDiagnostics(
        string runDirectory,
        PackagesCheckRequestFile request,
        PackagesCheckOutcomeFile outcome,
        string stdout,
        string stderr)
    {
        try
        {
            Directory.CreateDirectory(runDirectory);
            WriteJsonAtomically(
                Path.Combine(runDirectory, "request.recovered.json"),
                request,
                PackagesProofJsonContext.Default.PackagesCheckRequestFile);
            WriteJsonAtomically(
                Path.Combine(runDirectory, "outcome.recovered.json"),
                outcome,
                PackagesProofJsonContext.Default.PackagesCheckOutcomeFile);
            File.WriteAllText(Path.Combine(runDirectory, "stdout.recovered.txt"), stdout);
            File.WriteAllText(Path.Combine(runDirectory, "stderr.recovered.txt"), stderr);
            return true;
        }
        catch (Exception ex) when (
            ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            return false;
        }
    }

    private static void WriteJsonAtomically<T>(
        string path,
        T value,
        JsonTypeInfo<T> typeInfo)
    {
        string temporaryPath = StageJson(path, value, typeInfo);
        try
        {
            CommitStagedJson(temporaryPath, path);
        }
        finally
        {
            File.Delete(temporaryPath);
        }
    }

    private static string StageJson<T>(
        string path,
        T value,
        JsonTypeInfo<T> typeInfo)
    {
        string directory = Path.GetDirectoryName(path)
            ?? throw new InvalidOperationException($"Path has no parent directory: {path}");
        Directory.CreateDirectory(directory);
        string temporaryPath = Path.Combine(
            directory,
            $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using FileStream stream = new(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None);
            JsonSerializer.Serialize(stream, value, typeInfo);
            stream.WriteByte((byte)'\n');
            stream.Flush(flushToDisk: true);
            return temporaryPath;
        }
        catch
        {
            File.Delete(temporaryPath);
            throw;
        }
    }

    private static void CommitStagedJson(string stagedPath, string destinationPath)
    {
        if (File.Exists(destinationPath))
        {
            File.Replace(stagedPath, destinationPath, destinationBackupFileName: null);
        }
        else
        {
            File.Move(stagedPath, destinationPath);
        }
    }
}

internal sealed class PackagesCheckRequestFile
{
    [JsonPropertyName("schemaVersion")]
    public string? SchemaVersion { get; set; }

    [JsonPropertyName("architecture")]
    public string? Architecture { get; set; }

    [JsonPropertyName("catalogSha256")]
    public string? CatalogSha256 { get; set; }

    [JsonPropertyName("entries")]
    public List<PackagesCheckEntryFile> Entries { get; set; } = [];
}

internal class PackagesCheckEntryFile
{
    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("bucket")]
    public string? Bucket { get; set; }
}

internal sealed class PackagesCheckOutcomeFile
{
    [JsonPropertyName("schemaVersion")]
    public string? SchemaVersion { get; set; }

    [JsonPropertyName("architecture")]
    public string? Architecture { get; set; }

    [JsonPropertyName("catalogSha256")]
    public string? CatalogSha256 { get; set; }

    [JsonPropertyName("host")]
    public PackagesCheckHostFile? Host { get; set; }

    [JsonPropertyName("completedAtUtc")]
    public DateTimeOffset? CompletedAtUtc { get; set; }

    [JsonPropertyName("fatalError")]
    public string? FatalError { get; set; }

    [JsonPropertyName("results")]
    public List<PackagesCheckResultFile?>? Results { get; set; }
}

internal sealed class PackagesCheckHostFile
{
    private string? _processorArchitectureW6432;

    [JsonPropertyName("osArchitecture")]
    public string? OsArchitecture { get; set; }

    [JsonPropertyName("processArchitecture")]
    public string? ProcessArchitecture { get; set; }

    [JsonPropertyName("processorArchitecture")]
    public string? ProcessorArchitecture { get; set; }

    [JsonPropertyName("processorArchitectureW6432")]
    public string? ProcessorArchitectureW6432
    {
        get => _processorArchitectureW6432;
        set
        {
            _processorArchitectureW6432 = value;
            ProcessorArchitectureW6432Present = true;
        }
    }

    [JsonIgnore]
    public bool ProcessorArchitectureW6432Present { get; private set; }

    [JsonPropertyName("wingetVersion")]
    public string? WingetVersion { get; set; }
}

internal sealed class PackagesCheckResultFile : PackagesCheckEntryFile
{
    [JsonPropertyName("succeeded")]
    public bool Succeeded { get; set; }

    [JsonPropertyName("method")]
    public string? Method { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}
