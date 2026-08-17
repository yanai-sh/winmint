using System.Text.Json;
using System.Text.Json.Nodes;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
    public const string ExpectedEvidenceSchemaVersion = "winmint.expected-evidence/v1";
    public const string ServicingStagesSchemaVersion = "winmint.servicing.stages/v1";
    public const string PreparedMediaAuditSchemaVersion = "winmint.prepared-media.audit/v1";
    public const string BundleSchemaVersion = GuestBundleWire.SchemaVersion;

    /// <summary>Guest path stamped into Winlogon Shell (offline); Machine setup verifies the same path.</summary>
    public const string ShellStampGuestPath = @"C:\Windows\WinMint\Supervisor.exe";

    /// <summary>
    /// Host-only DISM mount root (not guest durable state). Keeps mounts off workdir/.scratch trees —
    /// short path, single cleanup locus. Subdirs: mount, boot-mount.
    /// </summary>
    public static string HostServicingRoot { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "Servicing");

    public static string HostMountDir => Path.Combine(HostServicingRoot, "mount");

    public static string HostBootMountDir => Path.Combine(HostServicingRoot, "boot-mount");

    /// <summary>Smoke default: Windows 11 Pro on consumer multi-edition ARM64/x64 ISOs (Home=1, Home SL=2, Pro=3).
    /// MountInstallWim exports this index to a single-image WIM before mount (IMAGESERVICING invariant 8).</summary>
    public const int DefaultProWimIndex = 3;

    /// <summary>Materialize stages and run elevated ImageServicing against a Source ISO (default pwsh runner).</summary>
    public static Task<Result<ImageEvidence, Failure>> ApplyAsync(
        BuildArtifacts plan,
        ServicingRun run,
        CancellationToken ct = default) =>
        ApplyAsync(plan, run, new PwshElevatedPlanRunner(), ct);

    /// <summary>Materialize stages and run elevated ImageServicing against a Source ISO.</summary>
    public static async Task<Result<ImageEvidence, Failure>> ApplyAsync(
        BuildArtifacts plan,
        ServicingRun run,
        IElevatedPlanRunner runner,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(runner);

        if (string.IsNullOrWhiteSpace(run.WorkDirectory))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.workdir.missing", "WorkDirectory is required."));
        }

        if (string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.outputIso.missing",
                    "OutputIsoPath is required. HostCompile freezes the Output ISO path before Apply."));
        }

        if (string.IsNullOrWhiteSpace(run.SourceIsoPath) || !File.Exists(run.SourceIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.sourceIso.missing", $"Source ISO not found: {run.SourceIsoPath}"));
        }

        ServicingRun normalized = run with { OutputIsoPath = run.OutputIsoPath.Trim() };

        ServicingWorkspace workspace = new(normalized.WorkDirectory);
        Directory.CreateDirectory(workspace.Root);
        Directory.CreateDirectory(workspace.Logs);
        Directory.CreateDirectory(HostServicingRoot);

        Result<IReadOnlyList<ServicingStage>, Failure> materialized =
            await Materialize(plan, normalized, workspace, ct).ConfigureAwait(false);
        if (!materialized.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(materialized.Error);
        }

        // Materialize already wrote stages.json; that file is the seam (Invoke-ServicingPlan.ps1 reads it).
        Result<ElevatedRunOk, Failure> elevated = await runner.ExecuteAsync(workspace, ct)
            .ConfigureAwait(false);
        if (!elevated.IsOk)
        {
            // Invariant: never delete workdir on failure (or success) — caller owns lifetime.
            return Result.Fail<ImageEvidence, Failure>(elevated.Error);
        }

        return WriteEvidence(workspace, plan, normalized, materialized.Value);
    }

    public static string SerializeServicingStagesFile(
        IReadOnlyList<(ServicingOpcode Opcode, JsonObject Parameters)> stages)
    {
        JsonArray arr = [];
        foreach ((ServicingOpcode opcode, JsonObject parameters) in stages)
        {
            JsonNode stage = new JsonObject
            {
                ["opcode"] = opcode.ToString(),
                ["parameters"] = parameters.DeepClone(),
            };
            arr.Add(stage);
        }

        JsonObject doc = new()
        {
            ["schemaVersion"] = ServicingStagesSchemaVersion,
            ["stages"] = arr,
        };
        return doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>Guest code compiled into the Supervisor — Provisioning plus the contracts it links.</summary>
    private static readonly string[] SupervisorSourceProjects =
        ["WinMint.Provisioning", "WinMint.Contracts"];

    /// <summary>
    /// Refuses a compile whose published Supervisor predates guest source. Staging copies whatever it
    /// finds, so a forgotten republish once shipped an ISO whose guest behaviour silently predated the
    /// tree that built it — the machine then fails in ways the source no longer explains.
    /// </summary>
    /// <returns>Null when the publish is current, absent, or unverifiable.</returns>
    public static Failure? CheckSupervisorFreshness()
    {
        string? published = FindPublishedSupervisor();
        if (published is null)
        {
            return null; // Staging reports the missing publish with its own remedy.
        }

        string? staleSince = SupervisorSourceProjects
            .Select(static project => ToolkitRoot.TryFind("src", project))
            .Select(root => FindSourceNewerThan(published, root))
            .FirstOrDefault(static hit => hit is not null);

        return staleSince is null
            ? null
            : new Failure(
                "hostCompile.supervisor.stale",
                $"Published Supervisor predates '{staleSince}'. An ISO built now would ship guest code "
                + "that no longer matches this tree. Run: just publish-provisioning");
    }

    /// <returns>Null when the publish is current, absent, or unverifiable.</returns>
    public static Failure? CheckWinPeApplyFreshness()
    {
        string? published = FindPublishedWinPeApply();
        if (published is null)
        {
            return null;
        }

        string? staleSince = FindSourceNewerThan(published, ToolkitRoot.TryFind("src", "WinMint.WinPeApply"));
        return staleSince is null
            ? null
            : new Failure(
                "hostCompile.winPeApply.stale",
                $"Published WinMintApply predates '{staleSince}'. An ISO built now would ship a WinPE helper "
                + "that no longer matches this tree. Run: just publish-provisioning");
    }

    /// <summary>
    /// First <c>*.cs</c> under <paramref name="sourceRoot"/> newer than the published binary.
    /// Null when source is absent — a packaged toolkit ships without <c>src/</c> and cannot check.
    /// </summary>
    internal static string? FindSourceNewerThan(string publishedExe, string? sourceRoot)
    {
        if (sourceRoot is null || !Directory.Exists(sourceRoot))
        {
            return null;
        }

        // ponytail: mtime, not content hash — a clock skew or a no-op touch gives a false "stale".
        // Future source mtimes (clock jumped backward) are skew, not "edited after this publish".
        // Hash inputs only if that remaining noise (no-op touch in the past) becomes a problem.
        DateTime published = File.GetLastWriteTimeUtc(publishedExe);
        DateTime now = DateTime.UtcNow;
        return Directory
            .EnumerateFiles(sourceRoot, "*.cs", SearchOption.AllDirectories)
            .Where(static file =>
                !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .FirstOrDefault(file =>
            {
                DateTime source = File.GetLastWriteTimeUtc(file);
                return source <= now && source > published;
            });
    }
}
