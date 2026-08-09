using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public static class BuildPlan
{
    public const string ProfileSchemaVersion = "winmint.profile/v1";
    public const string JobsSchemaVersion = "winmint.jobs/v1";
    public const string StagesSchemaVersion = "winmint.servicing.stages/v1";

    public const string IrelandSetupLocale = "en-IE";
    public const int IrelandSetupGeoId = 68;

    public static Result<Profile, DocumentErrors> TryParseProfile(ReadOnlySpan<byte> utf8Json)
    {
        if (utf8Json.IsEmpty)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson("Document is empty."));
        }

        ProfileDocument? doc;
        try
        {
            doc = JsonSerializer.Deserialize(utf8Json, BuildPlanJsonContext.Default.ProfileDocument);
        }
        catch (JsonException ex)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson(ex.Message));
        }

        if (doc is null)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson("Document deserialized to null."));
        }

        List<DocumentError> issues = [];

        if (string.IsNullOrWhiteSpace(doc.SchemaVersion))
        {
            issues.Add(new DocumentError("document.schemaVersion.missing", "schemaVersion is required.", "schemaVersion"));
        }
        else if (!string.Equals(doc.SchemaVersion, ProfileSchemaVersion, StringComparison.Ordinal))
        {
            issues.Add(new DocumentError(
                "document.schemaVersion.unsupported",
                $"Unsupported schemaVersion '{doc.SchemaVersion}'. Expected '{ProfileSchemaVersion}'.",
                "schemaVersion"));
        }

        if (doc.Account is null)
        {
            issues.Add(new DocumentError("account.missing", "account is required.", "account"));
        }

        if (doc.Dma is null)
        {
            issues.Add(new DocumentError("dma.missing", "dma is required.", "dma"));
        }
        else if (doc.Dma.Settle is null)
        {
            issues.Add(new DocumentError("dma.settle.missing", "dma.settle is required.", "dma.settle"));
        }

        if (doc.Account is not null)
        {
            if (string.IsNullOrWhiteSpace(doc.Account.Mode))
            {
                issues.Add(new DocumentError("account.mode.missing", "account.mode is required.", "account.mode"));
            }
            else if (!string.Equals(doc.Account.Mode, AccountModeWire.LocalAutoLogon, StringComparison.Ordinal))
            {
                issues.Add(new DocumentError(
                    "account.mode.unsupported",
                    $"Unsupported account.mode '{doc.Account.Mode}'. Smoke supports {AccountModeWire.LocalAutoLogon} only.",
                    "account.mode"));
            }

            if (string.IsNullOrWhiteSpace(doc.Account.Username))
            {
                issues.Add(new DocumentError("account.username.missing", "account.username is required.", "account.username"));
            }
        }

        if (issues.Count > 0)
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(issues));
        }

        DmaSettleDocument settle = doc.Dma!.Settle!;
        if (string.IsNullOrWhiteSpace(settle.Locale)
            || string.IsNullOrWhiteSpace(settle.TimeZoneId)
            || settle.GeoId is null
            || settle.LocationServicesEnabled is null)
        {
            issues.Add(new DocumentError(
                "dma.settle.incomplete",
                "dma.settle requires locale, geoId, timeZoneId, and locationServicesEnabled.",
                "dma.settle"));
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(issues));
        }

        // Default true: metal contract shows OOBE Network; Smoke Profiles set false explicitly.
        bool requireWifi = doc.Account!.RequireWifiDuringOobe ?? true;

        string? password = doc.Account.Password;
        string? passwordPath = string.IsNullOrWhiteSpace(doc.Account.PasswordPath)
            ? null
            : doc.Account.PasswordPath.Trim();
        // Host materializes passwordPath via ProfileFile; BuildPlan stays pure (issue 91).
        if (!string.IsNullOrEmpty(password) && passwordPath is not null)
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError(
                    "account.password.sources.conflict",
                    "account.password and account.passwordPath cannot both be set.",
                    "account"),
            ]));
        }

        if (!ProductOfflinePolicies.TryNormalizeDohProvider(doc.Policies?.DohProvider, out string? doh, out string? dohError))
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError("policies.dohProvider.unsupported", dohError!, "policies.dohProvider"),
            ]));
        }

        PoliciesProfile? policies = null;
        if (doc.Policies is not null)
        {
            policies = new PoliciesProfile(
                doc.Policies.KeepCopilot ?? false,
                doh);
        }
        else if (doh is not null)
        {
            policies = new PoliciesProfile(KeepCopilot: false, DohProvider: doh);
        }

        DriversProfile? drivers = null;
        if (doc.Drivers is not null)
        {
            if (string.IsNullOrWhiteSpace(doc.Drivers.Source))
            {
                return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
                [
                    new DocumentError("drivers.source.missing", "drivers.source is required.", "drivers.source"),
                ]));
            }

            if (string.IsNullOrWhiteSpace(doc.Drivers.DeviceId))
            {
                return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
                [
                    new DocumentError("drivers.deviceId.missing", "drivers.deviceId is required.", "drivers.deviceId"),
                ]));
            }

            drivers = new DriversProfile(doc.Drivers.Source.Trim(), doc.Drivers.DeviceId.Trim());
        }

        DebloatMode debloatMode = DebloatMode.Online;
        if (doc.Debloat?.Mode is not null)
        {
            if (string.Equals(doc.Debloat.Mode, "online", StringComparison.OrdinalIgnoreCase))
            {
                debloatMode = DebloatMode.Online;
            }
            else if (string.Equals(doc.Debloat.Mode, "offline", StringComparison.OrdinalIgnoreCase))
            {
                debloatMode = DebloatMode.Offline;
            }
            else
            {
                return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
                [
                    new DocumentError(
                        "debloat.mode.unsupported",
                        $"Unsupported debloat.mode '{doc.Debloat.Mode}'. Expected online|offline.",
                        "debloat.mode"),
                ]));
            }
        }

        Profile profile = new(
            new AccountProfile(doc.Account.Username!, password, requireWifi, passwordPath),
            new DmaProfile(
                doc.Dma.Enabled ?? true,
                new DmaSettleTarget(
                    settle.Locale,
                    settle.GeoId.Value,
                    settle.TimeZoneId,
                    settle.LocationServicesEnabled.Value)),
            debloatMode,
            NormalizeRemoveList(doc.Debloat?.RemoveProvisionedAppx),
            NormalizeRemoveList(doc.Packages?.Winget),
            NormalizeRemoveList(doc.Packages?.WingetNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Scoop),
            NormalizeRemoveList(doc.Packages?.ScoopNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Wsl),
            NormalizeRemoveList(doc.Packages?.WslNeedsReboot),
            NormalizeRemoveList(doc.Debloat?.RemoveCapabilities),
            NormalizeRemoveList(doc.Debloat?.DisableOptionalFeatures),
            policies,
            drivers);

        return Result.Ok<Profile, DocumentErrors>(profile);
    }

    /// <summary>Inverse of <see cref="TryParseProfile"/> — omit empty packages/debloat objects (same as former host composer).</summary>
    public static byte[] SerializeProfile(Profile profile)
    {
        PackagesDocument? packages = null;
        if (profile.WingetPackages.Count > 0 || profile.WingetNeedsReboot.Count > 0
            || profile.ScoopPackages.Count > 0 || profile.ScoopNeedsReboot.Count > 0
            || profile.WslDistros.Count > 0 || profile.WslNeedsReboot.Count > 0)
        {
            packages = new PackagesDocument(
                profile.WingetPackages.Count == 0 ? null : profile.WingetPackages.ToArray(),
                profile.WingetNeedsReboot.Count == 0 ? null : profile.WingetNeedsReboot.ToArray(),
                profile.ScoopPackages.Count == 0 ? null : profile.ScoopPackages.ToArray(),
                profile.ScoopNeedsReboot.Count == 0 ? null : profile.ScoopNeedsReboot.ToArray(),
                profile.WslDistros.Count == 0 ? null : profile.WslDistros.ToArray(),
                profile.WslNeedsReboot.Count == 0 ? null : profile.WslNeedsReboot.ToArray());
        }

        DebloatDocument? debloat = null;
        if (profile.DebloatMode == DebloatMode.Offline
            || profile.RemoveProvisionedAppx.Count > 0
            || profile.RemoveCapabilities.Count > 0
            || profile.DisableOptionalFeatures.Count > 0)
        {
            debloat = new DebloatDocument(
                profile.DebloatMode == DebloatMode.Offline ? "offline" : null,
                profile.RemoveProvisionedAppx.Count == 0 ? null : profile.RemoveProvisionedAppx.ToArray(),
                profile.RemoveCapabilities.Count == 0 ? null : profile.RemoveCapabilities.ToArray(),
                profile.DisableOptionalFeatures.Count == 0 ? null : profile.DisableOptionalFeatures.ToArray());
        }

        PoliciesProfile effective = profile.EffectivePolicies;
        PoliciesDocument? policies = null;
        if (effective.KeepCopilot || !string.IsNullOrWhiteSpace(effective.DohProvider))
        {
            policies = new PoliciesDocument(
                effective.KeepCopilot ? true : null,
                string.IsNullOrWhiteSpace(effective.DohProvider) ? null : effective.DohProvider);
        }

        DriversDocument? drivers = profile.Drivers is null
            ? null
            : new DriversDocument(profile.Drivers.Source, profile.Drivers.DeviceId);

        ProfileDocument doc = new(
            ProfileSchemaVersion,
            new AccountDocument(
                AccountModeWire.LocalAutoLogon,
                profile.Account.Username,
                profile.Account.PasswordPath is null ? profile.Account.Password : null,
                profile.Account.RequireWifiDuringOobe,
                profile.Account.PasswordPath),
            new DmaDocument(
                profile.Dma.Enabled,
                new DmaSettleDocument(
                    profile.Dma.Settle.Locale,
                    profile.Dma.Settle.GeoId,
                    profile.Dma.Settle.TimeZoneId,
                    profile.Dma.Settle.LocationServicesEnabled)),
            debloat,
            packages,
            policies,
            drivers);

        return JsonSerializer.SerializeToUtf8Bytes(doc, BuildPlanJsonContext.Default.ProfileDocument);
    }

    private static PlanFailure? ValidateDrivers(DriversProfile drivers, RunOptions options)
    {
        if (!string.Equals(drivers.Source, SurfaceDriverCatalog.SourceSurfaceCatalog, StringComparison.OrdinalIgnoreCase))
        {
            return new PlanFailure(
                "drivers.source.unsupported",
                $"drivers.source '{drivers.Source}' is unsupported (only '{SurfaceDriverCatalog.SourceSurfaceCatalog}' in this vertical).");
        }

        if (!SurfaceDriverCatalog.TryGet(drivers.DeviceId, out SurfaceDriverDevice? device) || device is null)
        {
            return new PlanFailure(
                "drivers.deviceId.unknown",
                $"drivers.deviceId '{drivers.DeviceId}' is not in the Surface driver catalog.");
        }

        if (!string.IsNullOrWhiteSpace(options.ImageArchitecture))
        {
            string imageArch = SurfaceDriverCatalog.NormalizeArchitecture(options.ImageArchitecture);
            if (!string.Equals(imageArch, device.Architecture, StringComparison.OrdinalIgnoreCase))
            {
                return new PlanFailure(
                    "drivers.architecture.mismatch",
                    $"drivers.deviceId '{device.Id}' targets {device.Architecture}, but the image architecture is {options.ImageArchitecture}.");
            }
        }

        if (options.WindowsBuild is int build && build < device.MinimumWindowsBuild)
        {
            return new PlanFailure(
                "drivers.windowsBuild.tooLow",
                $"drivers.deviceId '{device.Id}' requires Windows build {device.MinimumWindowsBuild} or later; source build is {build}.");
        }

        return null;
    }

    private static string[] NormalizeRemoveList(string[]? raw)
    {
        if (raw is null || raw.Length == 0)
        {
            return [];
        }

        return raw
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static PlanFailure? ValidateNeedsRebootSubset(
        IReadOnlyList<string> packages,
        IReadOnlyList<string> needsReboot,
        string code,
        string needsName,
        string packagesName)
    {
        HashSet<string> set = new(packages, StringComparer.OrdinalIgnoreCase);
        foreach (string id in needsReboot)
        {
            if (!set.Contains(id))
            {
                return new PlanFailure(
                    code,
                    $"{needsName} id '{id}' is not in {packagesName}.");
            }
        }

        return null;
    }

    /// <summary>Derived network requirement — not authored in Profile JSON (issue 71).</summary>
    public static bool PlanRequiresNetwork(Profile profile) =>
        (profile.DebloatMode == DebloatMode.Online && profile.RemoveProvisionedAppx.Count > 0)
        || profile.WingetPackages.Count > 0
        || profile.ScoopPackages.Count > 0
        || profile.WslDistros.Count > 0;

    /// <summary>Cli plan-dump shape for <c>manifest.json</c> (includes RequiresNetwork — #90 honesty).</summary>
    public static string SerializeManifestDump(BuildManifest manifest)
    {
        var node = new System.Text.Json.Nodes.JsonObject
        {
            ["imageQuality"] = manifest.ImageQuality.ToString(),
            ["requiresNetwork"] = manifest.RequiresNetwork,
        };
        return node.ToJsonString(DumpJsonOptions);
    }

    public static string SerializeJobsDump(JobsArtifact jobs)
    {
        var node = new System.Text.Json.Nodes.JsonObject
        {
            ["schemaVersion"] = jobs.SchemaVersion,
            ["jobs"] = new System.Text.Json.Nodes.JsonArray(
                jobs.Jobs.Select(static j =>
                {
                    var obj = new System.Text.Json.Nodes.JsonObject
                    {
                        ["id"] = j.Id,
                        ["kind"] = j.Kind,
                        ["needsReboot"] = j.NeedsReboot,
                    };
                    if (j.PackageId is not null)
                    {
                        obj["packageId"] = j.PackageId;
                    }

                    if (j.WingetArchitecture is not null)
                    {
                        obj["wingetArchitecture"] = j.WingetArchitecture;
                    }

                    if (j.WslInstallKind is not null)
                    {
                        obj["wslInstallKind"] = j.WslInstallKind;
                    }

                    if (j.WslFromFileRepo is not null)
                    {
                        obj["wslFromFileRepo"] = j.WslFromFileRepo;
                    }

                    if (j.WslFromFileAssetNames is { Count: > 0 })
                    {
                        obj["wslFromFileAssetNames"] = new System.Text.Json.Nodes.JsonArray(
                            j.WslFromFileAssetNames.Select(static n => (System.Text.Json.Nodes.JsonNode)n).ToArray());
                    }

                    if (j.AuditStrict)
                    {
                        obj["auditStrict"] = true;
                    }

                    if (j.ScoopBuckets is { Count: > 0 })
                    {
                        obj["scoopBuckets"] = new System.Text.Json.Nodes.JsonArray(
                            j.ScoopBuckets.Select(static b => (System.Text.Json.Nodes.JsonNode)b).ToArray());
                    }

                    return (System.Text.Json.Nodes.JsonNode)obj;
                }).ToArray()),
        };
        return node.ToJsonString(DumpJsonOptions);
    }

    public static string SerializeStagesDump(ServicingStageList stages)
    {
        var node = new System.Text.Json.Nodes.JsonObject
        {
            ["schemaVersion"] = StagesSchemaVersion,
            ["stages"] = new System.Text.Json.Nodes.JsonArray(
                stages.Stages.Select(static s => (System.Text.Json.Nodes.JsonNode)new System.Text.Json.Nodes.JsonObject
                {
                    ["opcode"] = s.Opcode.ToString(),
                    ["parameters"] = new System.Text.Json.Nodes.JsonObject(
                        s.Parameters.Select(static kv =>
                            KeyValuePair.Create<string, System.Text.Json.Nodes.JsonNode?>(kv.Key, kv.Value))),
                }).ToArray()),
        };
        return node.ToJsonString(DumpJsonOptions);
    }

    private static readonly JsonSerializerOptions DumpJsonOptions = new() { WriteIndented = true };

    /// <summary>
    /// Host-facing plan honesty (Cli + Wizard). Warns when FirstLogon needs network; never a PlanFailure.
    /// </summary>
    public static string FormatPlanHonesty(BuildManifest manifest, bool requireWifiDuringOobe)
    {
        string wifi = requireWifiDuringOobe
            ? "requireWifiDuringOobe=true (OOBE may show Network page)"
            : "requireWifiDuringOobe=false (OOBE Network page hidden)";
        string head =
            $"requiresNetwork={(manifest.RequiresNetwork ? "true" : "false")}; {wifi}";
        if (!manifest.RequiresNetwork)
        {
            return head;
        }

        return head
            + Environment.NewLine
            + "Warning: FirstLogon needs outbound network (packages and/or online AppX removes).";
    }

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null)
    {
        RunOptions options = run ?? new RunOptions();

        if (string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(
                new PlanFailure("account.password.required", "Local autoLogon requires a non-empty password."));
        }

        foreach (string id in profile.RemoveProvisionedAppx)
        {
            if (!ProvisionedAppxCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.removeProvisionedAppx.unknown",
                        $"removeProvisionedAppx id '{id}' is not in the shipped provisioned AppX catalog."));
            }
        }

        foreach (string id in profile.RemoveCapabilities)
        {
            if (!CapabilityCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.removeCapabilities.unknown",
                        $"removeCapabilities id '{id}' is not in the shipped capability catalog."));
            }
        }

        foreach (string id in profile.DisableOptionalFeatures)
        {
            if (!OptionalFeatureCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.disableOptionalFeatures.unknown",
                        $"disableOptionalFeatures id '{id}' is not in the shipped optional-feature catalog."));
            }
        }

        PlanFailure? needsRebootFail = ValidateNeedsRebootSubset(
            profile.WingetPackages,
            profile.WingetNeedsReboot,
            "packages.wingetNeedsReboot.unknown",
            "wingetNeedsReboot",
            "packages.winget");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        needsRebootFail = ValidateNeedsRebootSubset(
            profile.ScoopPackages,
            profile.ScoopNeedsReboot,
            "packages.scoopNeedsReboot.unknown",
            "scoopNeedsReboot",
            "packages.scoop");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        needsRebootFail = ValidateNeedsRebootSubset(
            profile.WslDistros,
            profile.WslNeedsReboot,
            "packages.wslNeedsReboot.unknown",
            "wslNeedsReboot",
            "packages.wsl");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        if (profile.Drivers is not null)
        {
            PlanFailure? driverFail = ValidateDrivers(profile.Drivers, options);
            if (driverFail is not null)
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(driverFail);
            }
        }

        PackageCatalog catalog = options.PackageCatalog ?? PackageCatalog.Default;
        string imageArchitecture = PackageCatalog.EffectiveImageArchitecture(options);
        PackagePhase packagePhase = PackageCatalog.EffectivePackagePhase(profile, imageArchitecture);
        IReadOnlyList<string> wingetAuditTargets = catalog.ValidateProfilePackages(
            profile,
            imageArchitecture,
            out PlanFailure? catalogFail);
        if (catalogFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(catalogFail);
        }

        byte[]? wingetImportJson = null;
        if (packagePhase == PackagePhase.WingetImport && profile.WingetPackages.Count > 0)
        {
            wingetImportJson = WingetImportBuilder.BuildUtf8Json(
                profile.WingetPackages,
                catalog,
                imageArchitecture);
            if (wingetImportJson.Length == 0)
            {
                wingetImportJson = null;
            }
        }

        HashSet<string> wingetNeedsReboot = new(profile.WingetNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> scoopNeedsReboot = new(profile.ScoopNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> wslNeedsReboot = new(profile.WslNeedsReboot, StringComparer.OrdinalIgnoreCase);

        string unattendXml = BuildOobeUnattendXml(profile);

        PoliciesProfile policies = profile.EffectivePolicies;
        if (!ProductOfflinePolicies.TryNormalizeDohProvider(policies.DohProvider, out string? dohProvider, out string? dohPlanError))
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(
                new PlanFailure("policies.dohProvider.unsupported", dohPlanError!));
        }

        // Product-constant FirstLogon jobs (ADR-009) + keep-flag safety net when remove-list non-empty.
        // smoke.stub.* only when RunOptions.IncludeSmokeStubs (Smoke/acceptance harness).
        List<JobDescriptor> jobList = [];
        if (options.IncludeSmokeStubs)
        {
            jobList.Add(new JobDescriptor("smoke.stub.ready", "stub"));
            jobList.Add(new JobDescriptor("smoke.stub.complete", "stub"));
        }

        jobList.Add(new JobDescriptor("onedrive.uninstall", "onedrive.uninstall"));
        jobList.Add(new JobDescriptor("reservedStorage.disable", "reservedStorage.disable"));
        if (dohProvider is not null)
        {
            jobList.Add(new JobDescriptor($"doh.{dohProvider}", "doh.set", PackageId: dohProvider));
        }

        if (profile.RemoveProvisionedAppx.Count > 0 && profile.DebloatMode == DebloatMode.Online)
        {
            jobList.Add(new JobDescriptor("keepflag.appx.safetyNet", "appx.safetyNet"));
        }

        if (wingetImportJson is { Length: > 0 })
        {
            bool importReboot = profile.WingetPackages.Any(id => wingetNeedsReboot.Contains(id));
            jobList.Add(new JobDescriptor(
                "winget.import",
                "winget.import",
                PackageId: "winget-import.json",
                NeedsReboot: importReboot));
        }
        else
        {
            foreach (string packageId in profile.WingetPackages)
            {
                catalog.TryGetToolByInstallId(packageId, out PackageToolEntry? wingetTool);
                string? wingetArch = wingetTool is null
                    ? null
                    : PackageCatalog.ResolveWingetArchitectureFlag(wingetTool, imageArchitecture);
                jobList.Add(new JobDescriptor(
                    $"winget.{packageId}",
                    "winget",
                    PackageId: packageId,
                    NeedsReboot: wingetNeedsReboot.Contains(packageId),
                    WingetArchitecture: wingetArch));
            }
        }

        if (profile.ScoopPackages.Count > 0)
        {
            IReadOnlySet<string> scoopBuckets = catalog.ScoopBucketsForInstallIds(profile.ScoopPackages);
            bool batchReboot = profile.ScoopPackages.Any(id => scoopNeedsReboot.Contains(id));
            jobList.Add(new JobDescriptor(
                "scoop.batch",
                "scoop.batch",
                PackageId: string.Join(';', profile.ScoopPackages),
                NeedsReboot: batchReboot,
                ScoopBuckets: scoopBuckets.OrderBy(b => b, StringComparer.OrdinalIgnoreCase).ToArray()));
        }

        foreach (string distroToken in profile.WslDistros)
        {
            catalog.TryGetWslByProfileToken(distroToken, out WslDistroEntry? wslEntry);
            string installId = wslEntry?.InstallId ?? distroToken;
            string? installKind = wslEntry?.InstallKind;
            IReadOnlyList<string>? assetNames = wslEntry?.FromFileAssetNamesFor(imageArchitecture);
            jobList.Add(new JobDescriptor(
                $"wsl.{installId}",
                "wsl",
                PackageId: installId,
                NeedsReboot: wslNeedsReboot.Contains(distroToken),
                WslInstallKind: installKind,
                WslFromFileRepo: wslEntry?.FromFileRepo,
                WslFromFileAssetNames: assetNames is { Count: > 0 } ? assetNames : null));
        }

        if (options.PackageAuditStrict
            && wingetAuditTargets.Count > 0
            && string.Equals(imageArchitecture, "arm64", StringComparison.OrdinalIgnoreCase))
        {
            jobList.Add(new JobDescriptor(
                "package.auditNative",
                "package.auditNative",
                PackageId: string.Join(';', wingetAuditTargets),
                AuditStrict: true));
        }

        JobsArtifact jobs = new(JobsSchemaVersion, jobList);

        string laneName;
        string compression;
        string cleanup;
        if (options.ImageQuality == ImageQualityLane.Release)
        {
            laneName = "Release";
            compression = "max";
            cleanup = "full";
        }
        else
        {
            laneName = "Test";
            compression = "fast";
            cleanup = "skip";
        }

        List<ServicingStage> stageList =
        [
            new ServicingStage(
                ServicingOpcode.MountInstallWim,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.SourceIso] = options.SourceIsoPath ?? "",
                }),
        ];

        if (profile.RemoveProvisionedAppx.Count > 0 && profile.DebloatMode == DebloatMode.Offline)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveProvisionedAppx,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.PackageFamilyNames] = string.Join(';', profile.RemoveProvisionedAppx),
                }));
        }

        if (profile.RemoveCapabilities.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveCapabilities,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.CapabilityNames] = string.Join(';', profile.RemoveCapabilities),
                }));
        }

        if (profile.DisableOptionalFeatures.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.DisableOptionalFeatures,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.FeatureNames] = string.Join(';', profile.DisableOptionalFeatures),
                }));
        }

        bool injectDrivers = profile.Drivers is not null;
        if (injectDrivers)
        {
            SurfaceDriverDevice device = SurfaceDriverCatalog.Devices[profile.Drivers!.DeviceId];
            stageList.Add(new ServicingStage(
                ServicingOpcode.InjectDrivers,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.DeviceId] = device.Id,
                    [StageParams.DetailsUrl] = device.DetailsUrl,
                    [StageParams.ExpectedFileNameRegex] = device.ExpectedFileNameRegex,
                    [StageParams.MinimumWindowsBuild] = device.MinimumWindowsBuild.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    [StageParams.Architecture] = device.Architecture,
                }));
        }

        bool braveSelected = profile.WingetPackages.Any(
            id => string.Equals(id, ProductOfflinePolicies.BraveWingetId, StringComparison.OrdinalIgnoreCase));
        IReadOnlyList<OfflinePolicyRow> policyRows = ProductOfflinePolicies.Compose(
            keepCopilot: policies.KeepCopilot,
            includeBraveDebloat: braveSelected,
            includeDriverHygiene: injectDrivers);
        stageList.Add(new ServicingStage(
            ServicingOpcode.StampOfflinePolicies,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [StageParams.PolicySpecs] = ProductOfflinePolicies.EncodeSpecs(policyRows),
            }));

        stageList.Add(new ServicingStage(ServicingOpcode.StagePayload, new Dictionary<string, string>(StringComparer.Ordinal)));
        stageList.Add(new ServicingStage(ServicingOpcode.StageOobeUnattend, new Dictionary<string, string>(StringComparer.Ordinal)));

        stageList.Add(new ServicingStage(
            ServicingOpcode.StampOfflineShell,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [StageParams.ShellTarget] = "Supervisor.exe",
            }));

        stageList.Add(new ServicingStage(ServicingOpcode.PatchBootWimApply, new Dictionary<string, string>(StringComparer.Ordinal)));

        stageList.AddRange(
        [
            new ServicingStage(
                ServicingOpcode.ExportWim,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.Lane] = laneName,
                    [StageParams.Compression] = compression,
                    [StageParams.Cleanup] = cleanup,
                }),
            new ServicingStage(
                ServicingOpcode.BuildIso,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.OutputIso] = options.OutputIsoPath ?? "",
                }),
        ]);

        ServicingStageList stages = new(stageList);

        BuildArtifacts artifacts = new(
            new UnattendArtifact(unattendXml),
            jobs,
            stages,
            new DmaContract(profile.Dma.Enabled, profile.Dma.Enabled ? profile.Dma.Settle : null),
            new BuildManifest(options.ImageQuality, PlanRequiresNetwork(profile)),
            profile.Account,
            profile.RemoveProvisionedAppx,
            wingetImportJson,
            options.PackageStrict);

        return Result.Ok<BuildArtifacts, PlanFailure>(artifacts);
    }

    /// <summary>OOBE-phase unattend (specialize + oobeSystem) for WinPE apply — no windowsPE disk/ImageInstall.</summary>
    internal static string BuildOobeUnattendXml(Profile profile)
    {
        string user = XmlEscape(profile.Account.Username);
        string pass = XmlEscape(profile.Account.Password ?? "");
        // Official Unattend: show Network when false/omit; hide when true (Smoke headless). See BUILDPLAN.
        string hideWireless = profile.Account.RequireWifiDuringOobe ? "false" : "true";
        string specialize = BuildSpecializeXml(profile);

        return $$"""
            <?xml version="1.0" encoding="utf-8"?>
            <unattend xmlns="urn:schemas-microsoft-com:unattend">
              {{specialize}}
              <settings pass="oobeSystem">
                <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <OOBE>
                    <HideEULAPage>true</HideEULAPage>
                    <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                    <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                    <HideWirelessSetupInOOBE>{{hideWireless}}</HideWirelessSetupInOOBE>
                    <ProtectYourPC>3</ProtectYourPC>
                  </OOBE>
                  <UserAccounts>
                    <LocalAccounts>
                      <LocalAccount wcm:action="add">
                        <Name>{{user}}</Name>
                        <Group>Administrators</Group>
                        <Password>
                          <Value>{{pass}}</Value>
                          <PlainText>true</PlainText>
                        </Password>
                      </LocalAccount>
                    </LocalAccounts>
                  </UserAccounts>
                  <AutoLogon>
                    <Enabled>true</Enabled>
                    <Username>{{user}}</Username>
                    <Password>
                      <Value>{{pass}}</Value>
                      <PlainText>true</PlainText>
                    </Password>
                    <LogonCount>5</LogonCount>
                  </AutoLogon>
                </component>
              </settings>
            </unattend>
            """;
    }

    private static string BuildSpecializeXml(Profile profile) =>
        profile.Dma.Enabled
            ? $$"""
              <settings pass="specialize">
                <component name="Microsoft-Windows-International-Core" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <InputLocale>{{IrelandSetupLocale}}</InputLocale>
                  <SystemLocale>{{IrelandSetupLocale}}</SystemLocale>
                  <UILanguage>{{IrelandSetupLocale}}</UILanguage>
                  <UserLocale>{{IrelandSetupLocale}}</UserLocale>
                </component>
                <component name="Microsoft-Windows-Deployment" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <RunSynchronous>
                    <RunSynchronousCommand wcm:action="add">
                      <Order>1</Order>
                      <Description>WinMint DMA setup GeoID latch (Ireland {{IrelandSetupGeoId}})</Description>
                      <Path>reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control\Nls\Geo" /v Nation /t REG_SZ /d {{IrelandSetupGeoId}} /f</Path>
                    </RunSynchronousCommand>
                  </RunSynchronous>
                </component>
              </settings>
              """
            : string.Empty;

    private static string XmlEscape(string value) =>
        System.Security.SecurityElement.Escape(value) ?? string.Empty;

    private static DocumentErrors InvalidJson(string message) =>
        new([new DocumentError("document.invalidJson", message)]);
}

internal sealed record ProfileDocument(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("account")] AccountDocument? Account,
    [property: JsonPropertyName("dma")] DmaDocument? Dma,
    [property: JsonPropertyName("debloat")] DebloatDocument? Debloat,
    [property: JsonPropertyName("packages")] PackagesDocument? Packages,
    [property: JsonPropertyName("policies")] PoliciesDocument? Policies = null,
    [property: JsonPropertyName("drivers")] DriversDocument? Drivers = null);

internal sealed record DriversDocument(
    [property: JsonPropertyName("source")] string? Source,
    [property: JsonPropertyName("deviceId")] string? DeviceId);

internal sealed record PoliciesDocument(
    [property: JsonPropertyName("keepCopilot")] bool? KeepCopilot,
    [property: JsonPropertyName("dohProvider")] string? DohProvider);

internal sealed record PackagesDocument(
    [property: JsonPropertyName("winget")] string[]? Winget,
    [property: JsonPropertyName("wingetNeedsReboot")] string[]? WingetNeedsReboot,
    [property: JsonPropertyName("scoop")] string[]? Scoop,
    [property: JsonPropertyName("scoopNeedsReboot")] string[]? ScoopNeedsReboot,
    [property: JsonPropertyName("wsl")] string[]? Wsl,
    [property: JsonPropertyName("wslNeedsReboot")] string[]? WslNeedsReboot);

internal sealed record DebloatDocument(
    [property: JsonPropertyName("mode")] string? Mode,
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx,
    [property: JsonPropertyName("removeCapabilities")] string[]? RemoveCapabilities,
    [property: JsonPropertyName("disableOptionalFeatures")] string[]? DisableOptionalFeatures);

internal sealed record AccountDocument(
    [property: JsonPropertyName("mode")] string? Mode,
    [property: JsonPropertyName("username")] string? Username,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("requireWifiDuringOobe")] bool? RequireWifiDuringOobe,
    [property: JsonPropertyName("passwordPath")] string? PasswordPath = null);

internal sealed record DmaDocument(
    [property: JsonPropertyName("enabled")] bool? Enabled,
    [property: JsonPropertyName("settle")] DmaSettleDocument? Settle);

internal sealed record DmaSettleDocument(
    [property: JsonPropertyName("locale")] string? Locale,
    [property: JsonPropertyName("geoId")] int? GeoId,
    [property: JsonPropertyName("timeZoneId")] string? TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool? LocationServicesEnabled);

[JsonSerializable(typeof(ProfileDocument))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class BuildPlanJsonContext : JsonSerializerContext;
