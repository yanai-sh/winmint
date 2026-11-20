using System.Security.Cryptography;
using System.Text;
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
    /// short path, single cleanup locus. Subdirs: mount, boot-mount, quality-cache.
    /// </summary>
    public static string HostServicingRoot { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "Servicing");

    public static string HostMountDir => Path.Combine(HostServicingRoot, "mount");

    public static string HostBootMountDir => Path.Combine(HostServicingRoot, "boot-mount");

    public static string HostQualityCacheRoot => Path.Combine(HostServicingRoot, "quality-cache");

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

        File.Delete(workspace.UsbMediaReceipt);

        // At most one Output ISO per workdir; drop prior leaves before this Apply.
        _ = WorkdirOutputIsos.ClearPrior(workspace.Root, normalized.OutputIsoPath);

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
    /// <returns>Null when the publish is current, the exe is absent, or source is absent.</returns>
    public static Failure? CheckSupervisorFreshness() =>
        CheckPublishedBinaryFreshness(
            FindPublishedSupervisor(),
            SupervisorSourceProjects.Select(static project => ToolkitRoot.TryFind("src", project)),
            "hostCompile.supervisor.stale",
            "Supervisor",
            "just publish-provisioning");

    /// <returns>Null when the publish is current, the exe is absent, or source is absent.</returns>
    public static Failure? CheckWinPeApplyFreshness() =>
        CheckPublishedBinaryFreshness(
            FindPublishedWinPeApply(),
            [ToolkitRoot.TryFind("src", "WinMint.WinPeApply")],
            "hostCompile.winPeApply.stale",
            "WinMintApply",
            "just publish-provisioning");

    internal static Failure? CheckPublishedBinaryFreshness(
        string? publishedExe,
        IEnumerable<string?> sourceRoots,
        string code,
        string publishedLabel,
        string remedy)
    {
        if (publishedExe is null)
        {
            return null;
        }

        List<string> present = [];
        foreach (string? root in sourceRoots)
        {
            if (root is not null && Directory.Exists(root))
            {
                present.Add(root);
            }
        }

        if (present.Count == 0)
        {
            return null;
        }

        string stampPath = publishedExe + ".sha256";
        if (!File.Exists(stampPath))
        {
            return new Failure(
                code,
                $"Published {publishedLabel} has no source stamp beside '{publishedExe}'. An ISO built now would ship guest code that may not match this tree. Run: {remedy}");
        }

        string expected = File.ReadAllText(stampPath).Trim();
        string actual = ComputeSourceTreeDigest(present);
        return string.Equals(expected, actual, StringComparison.Ordinal)
            ? null
            : new Failure(
                code,
                $"Published {publishedLabel} source stamp does not match this tree. Run: {remedy}");
    }

    /// <summary>
    /// SHA-256 of sorted <c>*.cs</c> under the source roots. Path is <c>Project/relative</c> with
    /// <c>/</c>, then a newline, the file bytes, and a newline. <c>bin</c> and <c>obj</c> are skipped.
    /// </summary>
    internal static string ComputeSourceTreeDigest(IEnumerable<string> sourceRoots)
    {
        List<(string Path, string Full)> files = [];
        foreach (string root in sourceRoots)
        {
            string project = new DirectoryInfo(root).Name;
            foreach (string file in Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories))
            {
                if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                    || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
                {
                    continue;
                }

                string relative = Path.GetRelativePath(root, file).Replace('\\', '/');
                files.Add(($"{project}/{relative}", file));
            }
        }

        files.Sort(static (left, right) => string.CompareOrdinal(left.Path, right.Path));
        using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach ((string path, string full) in files)
        {
            hash.AppendData(Encoding.UTF8.GetBytes(path));
            hash.AppendData("\n"u8);
            hash.AppendData(File.ReadAllBytes(full));
            hash.AppendData("\n"u8);
        }

        return Convert.ToHexStringLower(hash.GetHashAndReset());
    }
}
