using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Stateful Living Draft owner; composition remains HostCompile's job.</summary>
internal sealed class WizardSession : IDisposable
{
    private readonly ISourceMediaProbe? _sourceMedia;
    private Profile? _profile;
    private HostComposeOptions? _options;
    private byte[]? _draftIdentity;
    private HostComposition? _approved;
    private long _approvedRevision = -1;
    private SourceMediaReview? _probe;
    private string? _savedPath;

    public WizardSession(ISourceMediaProbe? sourceMedia = null)
    {
        _sourceMedia = sourceMedia;
    }

    public SessionView View =>
        new(
            Revision,
            _probe,
            _approved?.Review,
            _savedPath,
            _approved is not null && _approvedRevision == Revision);

    public long Revision { get; private set; }

    public long UpdateDraft(Profile profile, HostComposeOptions options)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(options);
        Profile owned = SnapshotProfile(profile);
        HostComposeOptions ownedOptions = SnapshotOptions(options);
        byte[] identity = BuildPlan.SerializeProfile(owned);
        if (_draftIdentity is not null
            && identity.AsSpan().SequenceEqual(_draftIdentity)
            && _options is not null
            && OptionsEqual(_options, ownedOptions))
        {
            return Revision;
        }

        Revision++;
        _profile = owned;
        _options = ownedOptions;
        _draftIdentity = identity;
        _approved = null;
        _approvedRevision = -1;
        _probe = null;
        _savedPath = null;
        return Revision;
    }

    public long InvalidateDraft()
    {
        Revision++;
        _profile = null;
        _options = null;
        _draftIdentity = null;
        _approved = null;
        _approvedRevision = -1;
        _probe = null;
        _savedPath = null;
        return Revision;
    }

    public async Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
        CancellationToken cancellationToken = default)
    {
        if (_options is null)
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wizardSession.draft.missing", "Update the draft before probing."));
        }

        long revision = Revision;
        HostComposeOptions options = _options;
        Result<IReadOnlyList<WimIndexInfo>, Failure> result = await (_sourceMedia ?? SourceMediaProbe.Instance)
            .ListIndexesAsync(options.SourceIsoPath, cancellationToken)
            .ConfigureAwait(false);
        if (revision != Revision || !ReferenceEquals(options, _options))
        {
            return Result.Fail<IReadOnlyList<WimIndexInfo>, Failure>(
                new Failure("wizardSession.probe.stale", "Discarded source-media probe for an older draft."));
        }

        return result;
    }

    public async Task<Result<HostReview, Failure>> PlanAsync(
        CancellationToken cancellationToken = default)
    {
        if (_profile is null || _options is null)
        {
            return Result.Fail<HostReview, Failure>(
                new Failure("wizardSession.draft.missing", "Update the draft before planning."));
        }

        long revision = Revision;
        Profile profile = _profile;
        HostComposeOptions options = _options;
        Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeAsync(
                profile,
                options,
                _sourceMedia,
                cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        if (revision != Revision || !ReferenceEquals(profile, _profile) || !ReferenceEquals(options, _options))
        {
            return Result.Fail<HostReview, Failure>(
                new Failure("wizardSession.compose.stale", "Discarded composition for an older draft."));
        }

        if (!composed.IsOk)
        {
            return Result.Fail<HostReview, Failure>(
                new Failure(composed.Error.Code, composed.Error.Message));
        }

        _approved = composed.Value;
        _approvedRevision = revision;
        _probe = composed.Value.Review.SourceMedia;
        return Result.Ok<HostReview, Failure>(composed.Value.Review);
    }

    public Result<Unit, Failure> Save(string destinationPath)
    {
        if (_approved is null || _approvedRevision != Revision)
        {
            return Result.Fail<Unit, Failure>(
                new Failure("wizardSession.approval.missing", "Plan the current draft before saving."));
        }

        string destination;
        try
        {
            destination = Path.GetFullPath(destinationPath);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return Result.Fail<Unit, Failure>(new Failure("wizardSession.save.path", ex.Message));
        }

        string? passwordPath = _approved.Review.AuthoredProfile.Account.PasswordPath;
        if (!string.IsNullOrWhiteSpace(passwordPath)
            && !Path.IsPathFullyQualified(passwordPath)
            && _approved.SourceProfileDirectory is { } sourceDirectory
            && !PathsEqual(sourceDirectory, Path.GetDirectoryName(destination)))
        {
            return Result.Fail<Unit, Failure>(
                new Failure(
                    "account.passwordPath.relocation",
                    "A Profile with a relative passwordPath can only be overwritten in its original directory."));
        }

        string? directory = Path.GetDirectoryName(destination);
        if (string.IsNullOrWhiteSpace(directory))
        {
            return Result.Fail<Unit, Failure>(
                new Failure("wizardSession.save.path", "Destination directory is required."));
        }

        string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllBytes(temporary, _approved.GetProfileUtf8());
            File.Move(temporary, destination, overwrite: true);
            _savedPath = destination;
            return Result.Ok<Unit, Failure>(default);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            try { File.Delete(temporary); } catch { }
            return Result.Fail<Unit, Failure>(new Failure("wizardSession.save.failed", ex.Message));
        }
    }

    public Result<HostComposition, Failure> TryGetApplyComposition() =>
        _approved is not null && _approvedRevision == Revision
            ? Result.Ok<HostComposition, Failure>(_approved)
            : Result.Fail<HostComposition, Failure>(
                new Failure("wizardSession.approval.missing", "Plan the current draft before Apply."));

    public Result<Unit, Failure> AcknowledgeApplySuccess(HostComposition appliedComposition)
    {
        if (_approved is null
            || _approvedRevision != Revision
            || !ReferenceEquals(_approved, appliedComposition))
        {
            return Result.Fail<Unit, Failure>(
                new Failure("wizardSession.apply.stale", "Apply result does not match the current approval."));
        }

        _approved = null;
        _approvedRevision = -1;
        return Result.Ok<Unit, Failure>(default);
    }

    public void Dispose()
    {
        _approved = null;
        _approvedRevision = -1;
        _profile = null;
        _options = null;
        _draftIdentity = null;
        _probe = null;
    }

    private static Profile SnapshotProfile(Profile profile) =>
        profile with
        {
            Account = profile.Account with { },
            Dma = profile.Dma with { Settle = profile.Dma.Settle with { } },
            RemoveProvisionedAppx = Array.AsReadOnly(profile.RemoveProvisionedAppx.ToArray()),
            WingetPackages = Array.AsReadOnly(profile.WingetPackages.ToArray()),
            WingetNeedsReboot = Array.AsReadOnly(profile.WingetNeedsReboot.ToArray()),
            ScoopPackages = Array.AsReadOnly(profile.ScoopPackages.ToArray()),
            ScoopNeedsReboot = Array.AsReadOnly(profile.ScoopNeedsReboot.ToArray()),
            WslDistros = Array.AsReadOnly(profile.WslDistros.ToArray()),
            WslNeedsReboot = Array.AsReadOnly(profile.WslNeedsReboot.ToArray()),
            RemoveCapabilities = Array.AsReadOnly(profile.RemoveCapabilities.ToArray()),
            DisableOptionalFeatures = Array.AsReadOnly(profile.DisableOptionalFeatures.ToArray()),
        };

    private static HostComposeOptions SnapshotOptions(HostComposeOptions options) =>
        options with
        {
            AuthoredSelectionLabels = options.AuthoredSelectionLabels is null
                ? null
                : Array.AsReadOnly(options.AuthoredSelectionLabels.ToArray()),
        };

    private static bool OptionsEqual(HostComposeOptions left, HostComposeOptions right) =>
        string.Equals(left.SourceIsoPath, right.SourceIsoPath, StringComparison.Ordinal)
        && left.ImageQuality == right.ImageQuality
        && string.Equals(left.WorkDirectory, right.WorkDirectory, StringComparison.Ordinal)
        && string.Equals(left.OutputIsoPath, right.OutputIsoPath, StringComparison.Ordinal)
        && left.WimIndex == right.WimIndex
        && left.PackageStrict == right.PackageStrict
        && left.PackageAuditStrict == right.PackageAuditStrict
        && left.IncludeSmokeStubs == right.IncludeSmokeStubs
        && string.Equals(left.ImageArchitecture, right.ImageArchitecture, StringComparison.Ordinal)
        && left.WindowsBuild == right.WindowsBuild
        && string.Equals(left.ProfileName, right.ProfileName, StringComparison.Ordinal)
        && ReferenceEquals(left.PackageCatalog, right.PackageCatalog)
        && (left.AuthoredSelectionLabels ?? []).SequenceEqual(
            right.AuthoredSelectionLabels ?? [],
            StringComparer.Ordinal);

    private static bool PathsEqual(string? left, string? right)
    {
        if (left is null || right is null) return false;
        return string.Equals(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)),
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)),
            StringComparison.OrdinalIgnoreCase);
    }
}

internal sealed record SessionView(
    long Revision,
    SourceMediaReview? SourceMedia,
    HostReview? Review,
    string? SavedPath,
    bool CanApply);
