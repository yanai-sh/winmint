using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Provisioning;

public readonly record struct BundleLoadError(string Code, string Message);

/// <summary>Load outcome for guest bundle + jobs.json (Provisioning-local; no Orchestrator ref).</summary>
public readonly struct BundleLoadResult
{
    private readonly ProvisioningBundle? _bundle;
    private readonly BundleLoadError _error;

    private BundleLoadResult(bool isOk, ProvisioningBundle? bundle, BundleLoadError error)
    {
        IsOk = isOk;
        _bundle = bundle;
        _error = error;
    }

    public bool IsOk { get; }

    public ProvisioningBundle Value => IsOk
        ? _bundle!
        : throw new InvalidOperationException("Bundle load failed.");

    public BundleLoadError Error => !IsOk
        ? _error
        : throw new InvalidOperationException("Bundle load succeeded.");

    public static BundleLoadResult Ok(ProvisioningBundle bundle) => new(true, bundle, default);

    public static BundleLoadResult Fail(BundleLoadError error) => new(false, null, error);
}

public static class BundleLoader
{
    public const string SchemaVersion = GuestBundleWire.SchemaVersion;
    public const string JobsSchemaVersion = JobsWire.SchemaVersion;
    public const string DefaultGuestBundlePath = @"C:\Windows\WinMint\bundle.json";
    public const string DefaultGuestWingetImportPath = @"C:\Windows\WinMint\winget-import.json";

    public static BundleLoadResult LoadFromFile(string path)
    {
        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.read", $"Failed to read bundle: {path}: {ex.Message}"));
        }

        BundleFile? file;
        try
        {
            file = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleFile);
        }
        catch (JsonException ex)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.parse", $"Failed to parse bundle: {path}: {ex.Message}"));
        }

        if (file is null)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.parse", $"Failed to parse bundle: {path}"));
        }

        if (!string.Equals(file.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError(
                    "bundle.schema",
                    $"Unsupported bundle schema '{file.SchemaVersion}' (need {SchemaVersion})."));
        }

        if (string.IsNullOrWhiteSpace(file.SupervisorPath))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.required", "bundle.supervisorPath is required."));
        }

        if (string.IsNullOrWhiteSpace(file.Username))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.required", "bundle.username is required."));
        }

        string? dir = Path.GetDirectoryName(path);
        string jobsPath = dir is null ? "jobs.json" : Path.Combine(dir, "jobs.json");
        if (!TryLoadJobs(jobsPath, out IReadOnlyList<ProvisionJob> jobs, out BundleLoadError jobsError))
        {
            return BundleLoadResult.Fail(jobsError);
        }

        return BundleLoadResult.Ok(
            new ProvisioningBundle(
                Account: new AccountStamp(file.Username, file.Password ?? ""),
                Dma: new DmaSettleTarget(
                    file.DmaEnabled,
                    file.Settle?.Locale,
                    file.Settle?.GeoId,
                    file.Settle?.TimeZoneId,
                    file.Settle?.LocationServicesEnabled),
                Jobs: jobs,
                Policy: SessionPolicy.SmokeDefaults,
                SupervisorShellPath: file.SupervisorPath,
                RemoveProvisionedAppx: file.RemoveProvisionedAppx ?? [],
                RequiresNetwork: file.RequiresNetwork,
                PackageStrict: file.PackageStrict));
    }

    private static bool TryLoadJobs(
        string jobsPath,
        out IReadOnlyList<ProvisionJob> jobs,
        out BundleLoadError error)
    {
        jobs = [];
        error = default;

        if (!File.Exists(jobsPath))
        {
            error = new BundleLoadError("jobs.missing", $"jobs.json required beside bundle (missing: {jobsPath}).");
            return false;
        }

        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(jobsPath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            error = new BundleLoadError("jobs.read", $"Failed to read jobs: {jobsPath}: {ex.Message}");
            return false;
        }

        JobsFile? jobsFile;
        try
        {
            jobsFile = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.JobsFile);
        }
        catch (JsonException ex)
        {
            error = new BundleLoadError("jobs.parse", $"Failed to parse jobs: {jobsPath}: {ex.Message}");
            return false;
        }

        if (jobsFile is null)
        {
            error = new BundleLoadError("jobs.parse", $"Failed to parse jobs: {jobsPath}");
            return false;
        }

        if (!string.Equals(jobsFile.SchemaVersion, JobsSchemaVersion, StringComparison.Ordinal))
        {
            error = new BundleLoadError(
                "jobs.schema",
                $"Unsupported jobs schema '{jobsFile.SchemaVersion}' (need {JobsSchemaVersion}).");
            return false;
        }

        List<ProvisionJob> list = [];
        foreach (JobFile j in jobsFile.Jobs ?? [])
        {
            if (!ProvisionJobKindWire.TryParse(j.Kind, out ProvisionJobKind kind))
            {
                error = new BundleLoadError(
                    "jobs.kind.unknown",
                    $"Unsupported job kind '{j.Kind}' for id '{j.Id}'.");
                return false;
            }

            WslInstallKind? wslKind = null;
            if (j.WslInstallKind is not null)
            {
                if (!WslInstallKindWire.TryParse(j.WslInstallKind, out WslInstallKind parsed))
                {
                    error = new BundleLoadError(
                        "jobs.wslInstallKind.unknown",
                        $"Unsupported wslInstallKind '{j.WslInstallKind}' for id '{j.Id}'.");
                    return false;
                }

                wslKind = parsed;
            }

            list.Add(
                new ProvisionJob(
                    j.Id,
                    kind,
                    j.NeedsReboot,
                    j.PackageId,
                    j.WingetArchitecture,
                    wslKind,
                    j.WslFromFileRepo,
                    j.WslFromFileAssetNames,
                    j.AuditStrict ?? false,
                    j.ScoopBuckets,
                    j.DohPrimary,
                    j.DohSecondary,
                    j.DohTemplate));
        }

        jobs = list.ToArray();
        return true;
    }
}


[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(JobsFile))]
[JsonSerializable(typeof(ProvisioningEvidenceFile))]
[JsonSerializable(typeof(PackagesEvidenceFile))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ProvisioningJsonContext : JsonSerializerContext;
