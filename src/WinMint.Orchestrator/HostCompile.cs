using System.Collections.ObjectModel;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>Orchestrator Profile → immutable approval → ImageServicing entry.</summary>
public static class HostCompile
{
    public static Result<HostPlan, HostComposeError> PlanDocument(
        Profile profile,
        HostComposeOptions? options = null)
    {
        ArgumentNullException.ThrowIfNull(profile);
        Profile owned = SnapshotProfile(profile);
        HostComposeOptions compose = options ?? new HostComposeOptions();
        RunOptions run = ToRunOptions(compose);
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(owned, run);
        if (!planned.IsOk)
        {
            return ComposeFail<HostPlan>(planned.Error);
        }

        BuildArtifacts snapshot = SnapshotArtifacts(planned.Value);
        return Result.Ok<HostPlan, HostComposeError>(
            new HostPlan(snapshot, CreateReview(owned, snapshot, null, null, null, "profile", compose.AuthoredSelectionLabels)));
    }

    public static Result<Unit, Failure> ExportPlan(HostPlan plan, string destinationDirectory)
    {
        ArgumentNullException.ThrowIfNull(plan);
        if (string.IsNullOrWhiteSpace(destinationDirectory))
        {
            return Result.Fail<Unit, Failure>(
                new Failure("hostPlan.destination.missing", "Destination directory is required."));
        }

        try
        {
            string destination = Path.GetFullPath(destinationDirectory);
            Directory.CreateDirectory(destination);
            BuildArtifacts artifacts = plan.Artifacts;
            File.WriteAllText(Path.Combine(destination, "unattend.xml"), artifacts.Unattend.Xml);
            File.WriteAllText(Path.Combine(destination, "jobs.json"), JobsWire.Write(artifacts.Jobs.Jobs));
            File.WriteAllText(
                Path.Combine(destination, "stages.json"),
                BuildPlan.SerializePlanStagesFile(
                    artifacts.Stages,
                    artifacts.Drivers,
                    artifacts.Manifest.ImageQuality));
            File.WriteAllText(Path.Combine(destination, "manifest.json"), BuildPlan.SerializeManifestFile(artifacts.Manifest));
            return Result.Ok<Unit, Failure>(default);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return Result.Fail<Unit, Failure>(new Failure("hostPlan.export.failed", ex.Message));
        }
    }

    public static Task<Result<HostComposition, HostComposeError>> ComposeAsync(
        Profile profile,
        HostComposeOptions options,
        ISourceMediaProbe? sourceMedia = null,
        TimeProvider? time = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            string? sourceDirectory = !string.IsNullOrWhiteSpace(options.ProfileName)
                && Path.IsPathFullyQualified(options.ProfileName)
                    ? Path.GetDirectoryName(Path.GetFullPath(options.ProfileName))
                    : null;
            return ComposeCoreAsync(profile, options, sourceDirectory, sourceMedia, time, cancellationToken);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return Task.FromResult(Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError("hostCompose.path.invalid", ex.Message)));
        }
    }

    public static async Task<Result<HostComposition, HostComposeError>> ComposeFileAsync(
        string profilePath,
        HostComposeOptions options,
        ISourceMediaProbe? sourceMedia = null,
        TimeProvider? time = null,
        CancellationToken cancellationToken = default)
    {
        Result<Profile, IReadOnlyList<DocumentError>> loaded = ProfileFile.TryLoad(profilePath);
        if (!loaded.IsOk)
        {
            IReadOnlyList<DocumentError> documents = Array.AsReadOnly(loaded.Error.ToArray());
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError(
                    "hostCompose.profile.invalid",
                    string.Join("; ", documents.Select(static item => $"{item.Code}: {item.Message}")),
                    documents));
        }

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(profilePath);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError("hostCompose.profile.invalid", ex.Message));
        }

        HostComposeOptions named = options with { ProfileName = fullPath };
        return await ComposeCoreAsync(
                loaded.Value,
                named,
                Path.GetDirectoryName(fullPath),
                sourceMedia,
                time,
                cancellationToken)
            .ConfigureAwait(false);
    }

    public static async Task<Result<ImageEvidence, Failure>> ApplyAsync(
        HostComposition composition,
        IElevatedPlanRunner? runner = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(composition);

        SourceIsoIdentity frozen = composition.Review.SourceMedia!.SourceIso;
        Result<bool, Failure> same =
            await frozen.MatchesCurrentAsync(composition.SourceIsoPath, cancellationToken).ConfigureAwait(false);
        if (!same.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(same.Error);
        }

        if (!same.Value)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "hostCompile.sourceIso.changed",
                    "Source ISO changed after composition; compose again before Apply."));
        }

        Directory.CreateDirectory(composition.WorkDirectory);
        ServicingRun run = new(
            composition.SourceIsoPath,
            composition.WorkDirectory,
            composition.OutputIsoPath,
            composition.Review.SourceMedia.Selected!.Index,
            frozen.Sha256,
            frozen.Length,
            composition.Review.SourceMedia.Selected);
        return await ImageServicing.ApplyAsync(
                composition.Artifacts,
                run,
                runner ?? new PwshElevatedPlanRunner(),
                cancellationToken)
            .ConfigureAwait(false);
    }

    private static async Task<Result<HostComposition, HostComposeError>> ComposeCoreAsync(
        Profile profile,
        HostComposeOptions options,
        string? sourceProfileDirectory,
        ISourceMediaProbe? sourceMedia,
        TimeProvider? time,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(options);
        IReadOnlyList<string> authoredSelectionLabels = ReadOnly(
            options.AuthoredSelectionLabels
                ?.Where(static label => !string.IsNullOrWhiteSpace(label))
                .Select(static label => label.Trim())
            ?? []);
        if (string.IsNullOrWhiteSpace(options.SourceIsoPath))
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError("hostCompose.sourceIso.missing", "Source ISO path is required."));
        }

        string source;
        string work;
        string output;
        try
        {
            source = Path.GetFullPath(options.SourceIsoPath.Trim());
            work = Path.GetFullPath(HostDefaults.ResolveWorkDirectory(options.ImageQuality, options.WorkDirectory));
            string stem = OutputIsoNaming.ProfileStem(options.ProfileName);
            output = string.IsNullOrWhiteSpace(options.OutputIsoPath)
                ? OutputIsoNaming.DefaultPath(work, stem + ".profile.json", options.ImageQuality, time)
                : Path.GetFullPath(options.OutputIsoPath.Trim());
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError("hostCompose.path.invalid", ex.Message));
        }

        int selectedIndex = options.WimIndex ?? ImageServicing.DefaultProWimIndex;
        Result<SourceMediaReview, Failure> probed = await (sourceMedia ?? SourceMediaProbe.Instance)
            .ProbeAsync(source, selectedIndex, cancellationToken)
            .ConfigureAwait(false);
        if (!probed.IsOk)
        {
            return ComposeFail<HostComposition>(probed.Error);
        }

        SourceMediaReview media = SnapshotMedia(probed.Value);
        if (media.Selected is null)
        {
            SourceMediaSelectionMismatch mismatch = media.SelectionMismatch
                ?? new SourceMediaSelectionMismatch(
                    selectedIndex,
                    "wim.probe.indexMissing",
                    $"Source ISO does not contain WIM index {selectedIndex}.");
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError(mismatch.Code, mismatch.Message));
        }
        if (string.IsNullOrWhiteSpace(media.Selected.Name)
            || string.IsNullOrWhiteSpace(media.Selected.Architecture)
            || string.IsNullOrWhiteSpace(media.Selected.Edition)
            || string.IsNullOrWhiteSpace(media.Selected.Build))
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError(
                    "hostCompose.sourceMedia.incomplete",
                    "Selected WIM must report name, architecture, edition, and build."));
        }
        string selectedArchitecture = PackageCatalog.NormalizeArch(media.Selected.Architecture);
        if (!string.IsNullOrWhiteSpace(options.ImageArchitecture)
            && !string.Equals(
                PackageCatalog.NormalizeArch(options.ImageArchitecture),
                selectedArchitecture,
                StringComparison.Ordinal))
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError(
                    "hostCompose.imageArchitecture.mismatch",
                    $"Selected WIM architecture '{media.Selected.Architecture}' does not match '{options.ImageArchitecture}'."));
        }

        int? selectedBuild = int.TryParse(media.Selected.Build, out int parsedBuild) ? parsedBuild : null;
        if (options.WindowsBuild is int expectedBuild && selectedBuild != expectedBuild)
        {
            return Result.Fail<HostComposition, HostComposeError>(
                new HostComposeError(
                    "hostCompose.windowsBuild.mismatch",
                    $"Selected WIM build '{media.Selected.Build}' does not match '{expectedBuild}'."));
        }

        Profile ownedProfile = SnapshotProfile(profile);
        byte[] canonical = BuildPlan.SerializeProfile(ownedProfile);
        RunOptions run = ToRunOptions(options, source, output, selectedArchitecture, selectedBuild);
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(ownedProfile, run);
        if (!planned.IsOk)
        {
            return ComposeFail<HostComposition>(planned.Error);
        }

        BuildArtifacts snapshot = SnapshotArtifacts(planned.Value);
        string stemValue = OutputIsoNaming.ProfileStem(options.ProfileName);
        HostReview review = CreateReview(
            ownedProfile,
            snapshot,
            media,
            work,
            output,
            stemValue,
            authoredSelectionLabels);
        return Result.Ok<HostComposition, HostComposeError>(
            new HostComposition(
                snapshot,
                review,
                canonical,
                sourceProfileDirectory,
                source,
                work,
                output));
    }

    private static HostReview CreateReview(
        Profile profile,
        BuildArtifacts artifacts,
        SourceMediaReview? media,
        string? work,
        string? output,
        string profileStem,
        IEnumerable<string>? authoredSelectionLabels) =>
        new(
            SnapshotProfile(profile) with
            {
                Account = profile.Account with { Password = null },
            },
            System.Text.Encoding.UTF8.GetString(BuildPlan.SerializeProfile(
                SnapshotProfile(profile) with
                {
                    Account = profile.Account with { Password = null },
                })),
            media,
            work,
            output,
            profileStem,
            artifacts.Manifest.ImageQuality,
            artifacts.PackageStrict,
            artifacts.Manifest.RequiresNetwork,
            ReadOnly(artifacts.RemoveProvisionedAppx),
            ReadOnly(artifacts.EffectivePackages),
            ReadOnly(artifacts.Jobs.Jobs.Select(SnapshotJob)),
            ReadOnly(artifacts.Stages),
            artifacts.BraveSelected,
            ReadOnly(artifacts.EffectivePackages
                .Where(static package =>
                    package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store)
                .Select(static package => package.ResolvedInstallId)),
            ReadOnly(artifacts.EffectivePackages
                .Where(static package => package.Source == EffectivePackageSource.Scoop)
                .Select(static package => package.ResolvedInstallId)),
            ReadOnly(authoredSelectionLabels ?? []));

    private static Profile SnapshotProfile(Profile profile) =>
        profile with
        {
            Account = profile.Account with { },
            Dma = profile.Dma with { Settle = profile.Dma.Settle with { } },
            RemoveProvisionedAppx = ReadOnly(profile.RemoveProvisionedAppx),
            WingetPackages = ReadOnly(profile.WingetPackages),
            WingetNeedsReboot = ReadOnly(profile.WingetNeedsReboot),
            ScoopPackages = ReadOnly(profile.ScoopPackages),
            ScoopNeedsReboot = ReadOnly(profile.ScoopNeedsReboot),
            WslDistros = ReadOnly(profile.WslDistros),
            WslNeedsReboot = ReadOnly(profile.WslNeedsReboot),
            RemoveCapabilities = ReadOnly(profile.RemoveCapabilities),
            DisableOptionalFeatures = ReadOnly(profile.DisableOptionalFeatures),
            Policies = profile.Policies is null ? null : profile.Policies with { },
            Drivers = profile.Drivers is null ? null : profile.Drivers with { },
        };

    private static RunOptions ToRunOptions(
        HostComposeOptions options,
        string? sourceIsoPath = null,
        string? outputIsoPath = null,
        string? imageArchitecture = null,
        int? windowsBuild = null) =>
        new()
        {
            ImageQuality = options.ImageQuality,
            SourceIsoPath = sourceIsoPath ?? NullIfEmpty(options.SourceIsoPath),
            OutputIsoPath = outputIsoPath ?? NullIfEmpty(options.OutputIsoPath),
            ImageArchitecture = imageArchitecture ?? NullIfEmpty(options.ImageArchitecture),
            WindowsBuild = windowsBuild ?? options.WindowsBuild,
            PackageAuditStrict = options.PackageAuditStrict,
            PackageStrict = HostDefaults.ResolvePackageStrict(options.ImageQuality, options.PackageStrict),
            IncludeSmokeStubs = options.IncludeSmokeStubs,
            PackageCatalog = options.PackageCatalog,
        };

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    private static BuildArtifacts SnapshotArtifacts(BuildArtifacts artifacts) =>
        new(
            artifacts.Unattend with { },
            new JobsArtifact(artifacts.Jobs.SchemaVersion, ReadOnly(artifacts.Jobs.Jobs.Select(SnapshotJob))),
            ReadOnly(artifacts.Stages),
            artifacts.Dma with
            {
                Settle = artifacts.Dma.Settle is null ? null : artifacts.Dma.Settle with { },
            },
            artifacts.Manifest with { },
            artifacts.Account with { },
            ReadOnly(artifacts.RemoveProvisionedAppx),
            ReadOnly(artifacts.EffectivePackages),
            ReadOnly(artifacts.OfflinePolicies),
            ReadOnly(artifacts.RemoveCapabilities),
            ReadOnly(artifacts.DisableOptionalFeatures),
            artifacts.WingetImportJson?.ToArray(),
            artifacts.PackageStrict,
            artifacts.BraveSelected,
            artifacts.Drivers);

    private static ProvisionJob SnapshotJob(ProvisionJob job) =>
        job with
        {
            WslFromFileAssetNames = job.WslFromFileAssetNames is null ? null : ReadOnly(job.WslFromFileAssetNames),
            ScoopBuckets = job.ScoopBuckets is null ? null : ReadOnly(job.ScoopBuckets),
        };

    private static SourceMediaReview SnapshotMedia(SourceMediaReview media) =>
        media with
        {
            Indexes = ReadOnly(media.Indexes.Select(static row => row with { })),
            Selected = media.Selected is null ? null : media.Selected with { },
            SelectionMismatch = media.SelectionMismatch is null ? null : media.SelectionMismatch with { },
        };

    private static ReadOnlyCollection<T> ReadOnly<T>(IEnumerable<T> values) =>
        Array.AsReadOnly(values.ToArray());

    private static Result<T, HostComposeError> ComposeFail<T>(Failure failure) =>
        Result.Fail<T, HostComposeError>(new HostComposeError(failure.Code, failure.Message));
}

public sealed record HostComposeOptions(
    string SourceIsoPath = "",
    ImageQualityLane ImageQuality = ImageQualityLane.Test,
    string? WorkDirectory = null,
    string? OutputIsoPath = null,
    int? WimIndex = null,
    PackageStrictOverride PackageStrict = PackageStrictOverride.FromLane,
    bool PackageAuditStrict = false,
    bool IncludeSmokeStubs = false,
    string? ImageArchitecture = null,
    int? WindowsBuild = null,
    string? ProfileName = null,
    PackageCatalog? PackageCatalog = null,
    IReadOnlyList<string>? AuthoredSelectionLabels = null);

public sealed record HostComposeError(
    string Code,
    string Message,
    IReadOnlyList<DocumentError>? Documents = null);

public sealed record HostReview(
    Profile AuthoredProfile,
    string AuthoredProfileJson,
    SourceMediaReview? SourceMedia,
    string? WorkDirectory,
    string? OutputIsoPath,
    string ProfileStem,
    ImageQualityLane ImageQuality,
    bool PackageStrict,
    bool RequiresNetwork,
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<EffectivePackageFact> EffectivePackages,
    IReadOnlyList<ProvisionJob> Jobs,
    IReadOnlyList<ServicingOpcode> Stages,
    bool BraveSelected,
    IReadOnlyList<string> EffectiveWinget,
    IReadOnlyList<string> EffectiveScoop,
    IReadOnlyList<string> AuthoredSelectionLabels)
{
    public bool IsGateB => ImageQuality == ImageQualityLane.Release && PackageStrict;

    public string Honesty
    {
        get
        {
            string wifi = AuthoredProfile.Account.RequireWifiDuringOobe
                ? "requireWifiDuringOobe=true (OOBE may show Network page)"
                : "requireWifiDuringOobe=false (OOBE Network page hidden)";
            string head = $"requiresNetwork={(RequiresNetwork ? "true" : "false")}; {wifi}";
            return RequiresNetwork
                ? head + Environment.NewLine
                    + "Warning: FirstLogon needs outbound network (packages and/or online AppX removes)."
                : head;
        }
    }

    public string Diff => PlanDiff.Format(this);

    public string QuietSummary =>
        RemoveProvisionedAppx.Count > 0
            ? $"This build strips {RemoveProvisionedAppx.Count} apps."
            : "This build applies product defaults.";

    public string PickStrip
    {
        get
        {
            string[] labels = AuthoredSelectionLabels
                .Where(static label => !string.IsNullOrWhiteSpace(label))
                .Select(static label => label.Trim())
                .ToArray();
            return labels.Length == 0 ? string.Empty : string.Join(" · ", labels);
        }
    }

    public string QuietBlock
    {
        get
        {
            List<string> parts = [.. ProductPosture.QuietLabels];
            if (BraveSelected)
            {
                parts.Add("Brave policies");
            }

            return "Also applied quietly: " + string.Join(" · ", parts);
        }
    }

    public string WhatsIncluded => string.Join(" · ", PlanDiff.FriendlyRemoveNames(RemoveProvisionedAppx));

    public string PlanMeta =>
        $"Account {AuthoredProfile.Account.Username.Trim()} · region {AuthoredProfile.Dma.Settle.Locale} / {AuthoredProfile.Dma.Settle.TimeZoneId} · network {(RequiresNetwork ? "needed" : "not needed")} · DMA {(AuthoredProfile.Dma.Enabled ? "on" : "off")} · {ImageQuality} lane";
}

public sealed class HostComposition
{
    private readonly BuildArtifacts _artifacts;
    private readonly byte[] _profileUtf8;

    internal HostComposition(
        BuildArtifacts artifacts,
        HostReview review,
        byte[] profileUtf8,
        string? sourceProfileDirectory,
        string sourceIsoPath,
        string workDirectory,
        string outputIsoPath)
    {
        _artifacts = artifacts;
        Review = review;
        _profileUtf8 = profileUtf8.ToArray();
        SourceProfileDirectory = sourceProfileDirectory;
        SourceIsoPath = sourceIsoPath;
        WorkDirectory = workDirectory;
        OutputIsoPath = outputIsoPath;
    }

    public HostReview Review { get; }
    public string SourceIsoPath { get; }
    public string WorkDirectory { get; }
    public string OutputIsoPath { get; }
    public byte[] GetProfileUtf8() => _profileUtf8.ToArray();
    internal BuildArtifacts Artifacts => _artifacts;
    public string? SourceProfileDirectory { get; }
}

public sealed class HostPlan
{
    internal HostPlan(BuildArtifacts artifacts, HostReview review)
    {
        Artifacts = artifacts;
        Review = review;
    }

    public HostReview Review { get; }
    internal BuildArtifacts Artifacts { get; }
}

public readonly record struct Unit;
