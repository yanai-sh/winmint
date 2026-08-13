using System.Security.Cryptography;
using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

public class HostCompositionTests
{
    [Fact]
    public async Task Composition_freezes_review_plan_paths_media_and_profile_bytes()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            List<string> appx = ["Microsoft.GetHelp"];
            List<string> authoredSelections = ["Edge"];
            Profile profile = Profile(appx);
            DateTimeOffset instant = new(2026, 8, 12, 19, 20, 21, TimeSpan.Zero);
            Result<HostComposition, HostComposeError> result = await HostCompile.ComposeAsync(
                profile,
                new HostComposeOptions(
                    iso,
                    ImageQualityLane.Release,
                    Path.Combine(root, "work"),
                    WimIndex: 1,
                    ProfileName: "sl7.profile.json",
                    AuthoredSelectionLabels: authoredSelections),
                new RealHashProbe(),
                new FixedTimeProvider(instant),
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
            HostComposition composition = result.Value;
            appx.Add("Microsoft.ZuneMusic");
            authoredSelections.Add("Not frozen");
            byte[] first = composition.GetProfileUtf8();
            first.AsSpan().Fill((byte)'x');
            byte[] second = composition.GetProfileUtf8();

            Assert.Contains("Microsoft.GetHelp", composition.Review.RemoveProvisionedAppx);
            Assert.DoesNotContain("Microsoft.ZuneMusic", composition.Review.RemoveProvisionedAppx);
            Assert.NotEqual(first, second);
            Assert.Null(composition.Review.AuthoredProfile.Account.Password);
            Assert.DoesNotContain("lab-only", composition.Review.AuthoredProfileJson, StringComparison.Ordinal);
            Assert.DoesNotContain("\"password\"", composition.Review.AuthoredProfileJson, StringComparison.OrdinalIgnoreCase);
            Assert.Equal(ImageQualityLane.Release, composition.Review.ImageQuality);
            Assert.True(composition.Review.PackageStrict);
            Assert.Null(typeof(HostReview).GetProperty("ReuseMedia"));
            Assert.Null(typeof(HostComposeOptions).GetProperty("ReuseMedia"));
            Assert.Null(typeof(HostComposition).GetProperty("ReuseMedia"));
            Assert.Equal("sl7", composition.Review.ProfileStem);
            Assert.Equal(["Edge"], composition.Review.AuthoredSelectionLabels);
            string timestamp = instant.ToLocalTime().ToString(
                "yyyyMMdd-HHmmss",
                System.Globalization.CultureInfo.InvariantCulture);
            Assert.EndsWith(
                Path.Combine("work", $"winmint_sl7_Release_{timestamp}.iso"),
                composition.OutputIsoPath,
                StringComparison.OrdinalIgnoreCase);
            Assert.Equal(
                Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(iso))),
                composition.Review.SourceMedia!.SourceIsoSha256);
            Assert.Equal("ARM64", composition.Review.SourceMedia.Selected!.Architecture);

            ImageServicingTestFakes.RecordingElevatedPlanRunner runner = new();
            Assert.True((await HostCompile.ApplyAsync(
                composition,
                runner,
                TestContext.Current.CancellationToken)).IsOk);
            ServicingStage mount = Assert.Single(
                runner.Stages,
                stage => stage.Opcode == ServicingOpcode.MountInstallWim);
            Assert.False(mount.Parameters.ContainsKey("reuseMedia"));
            Assert.Equal(composition.Review.SourceMedia.SourceIsoSha256, mount.Parameters[StageParams.SourceIsoSha256]);
            Assert.Equal(
                MediaCacheIdentity.CurrentSchema.ToString(System.Globalization.CultureInfo.InvariantCulture),
                mount.Parameters[StageParams.CacheSchema]);
            Assert.Equal(MediaCacheIdentity.Root, mount.Parameters[StageParams.CacheRoot]);
            Assert.True(long.TryParse(mount.Parameters[StageParams.SourceIsoLength], out long isoLength));
            Assert.Equal(new FileInfo(iso).Length, isoLength);
            Assert.Equal(composition.Review.SourceMedia.Selected.Name, mount.Parameters[StageParams.ImageName]);
            Assert.Equal(composition.OutputIsoPath, Assert.Single(
                runner.Stages,
                stage => stage.Opcode == ServicingOpcode.BuildIso).Parameters[StageParams.OutputIso]);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Apply_rejects_changed_source_before_elevation()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            HostComposition composition = (await HostCompile.ComposeAsync(
                Profile([]),
                new HostComposeOptions(iso, WorkDirectory: Path.Combine(root, "work"), WimIndex: 1),
                new RealHashProbe(),
                cancellationToken: TestContext.Current.CancellationToken)).Value;
            File.AppendAllText(iso, "changed");
            CountingRunner runner = new();

            Result<ImageEvidence, Failure> applied = await HostCompile.ApplyAsync(
                composition,
                runner,
                TestContext.Current.CancellationToken);

            Assert.False(applied.IsOk);
            Assert.Equal("hostCompile.sourceIso.changed", applied.Error.Code);
            Assert.Equal(0, runner.Calls);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Theory]
    [InlineData("aarch64", "ARM64")]
    [InlineData("arm64", "aarch64")]
    [InlineData("amd64", "x64")]
    [InlineData("x64", "AMD64")]
    public async Task Compose_compares_architecture_aliases_through_shared_normalization(
        string expected,
        string reported)
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            Result<HostComposition, HostComposeError> result = await HostCompile.ComposeAsync(
                Profile([]),
                new HostComposeOptions(
                    iso,
                    WorkDirectory: Path.Combine(root, "work"),
                    WimIndex: 1,
                    ImageArchitecture: expected),
                new ArchitectureProbe(reported),
                cancellationToken: TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task ComposeFile_preserves_structured_document_errors()
    {
        string root = NewRoot();
        try
        {
            string profile = Path.Combine(root, "bad.profile.json");
            File.WriteAllText(profile, """{"schemaVersion":"wrong"}""");
            Result<HostComposition, HostComposeError> result = await HostCompile.ComposeFileAsync(
                profile,
                new HostComposeOptions(Path.Combine(root, "missing.iso")),
                cancellationToken: TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            DocumentError error = result.Error.Documents![0];
            Assert.False(string.IsNullOrWhiteSpace(error.Code));
            Assert.False(string.IsNullOrWhiteSpace(error.Message));
            Assert.NotNull(error.Path);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Relative_password_path_saves_only_in_original_directory_without_rereading_secret()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            string secret = Path.Combine(root, "password.txt");
            File.WriteAllText(secret, "lab-only");
            string profilePath = Path.Combine(root, "loaded.profile.json");
            File.WriteAllText(profilePath, """
                {
                  "schemaVersion": "winmint.profile/v1",
                  "account": {
                    "mode": "localAutoLogon",
                    "username": "winmint",
                    "passwordPath": "password.txt",
                    "requireWifiDuringOobe": false
                  },
                  "dma": {
                    "enabled": true,
                    "settle": {
                      "locale": "en-GB",
                      "geoId": 242,
                      "timeZoneId": "GMT Standard Time",
                      "locationServicesEnabled": true
                    }
                  }
                }
                """);
            Result<Profile, IReadOnlyList<DocumentError>> loaded = ProfileFile.TryLoad(profilePath);
            Assert.True(loaded.IsOk);
            File.Delete(secret);

            WizardSession session = new(new FixedProbe());
            session.UpdateDraft(
                loaded.Value,
                new HostComposeOptions(
                    iso,
                    WorkDirectory: Path.Combine(root, "work"),
                    WimIndex: 1,
                    ProfileName: profilePath));
            Assert.True((await session.PlanAsync(TestContext.Current.CancellationToken)).IsOk);
            string overwrite = Path.Combine(root, "copy.profile.json");
            Assert.True(session.Save(overwrite).IsOk);
            string json = File.ReadAllText(overwrite);
            Assert.Contains("\"passwordPath\": \"password.txt\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("lab-only", json, StringComparison.Ordinal);

            string relocated = Path.Combine(root, "other", "copy.profile.json");
            Result<Unit, Failure> rejected = session.Save(relocated);
            Assert.False(rejected.IsOk);
            Assert.Equal("account.passwordPath.relocation", rejected.Error.Code);
            Assert.False(File.Exists(relocated));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Exported_profile_changes_cannot_change_the_approved_apply()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            string profilePath = Path.Combine(root, "original.profile.json");
            File.WriteAllBytes(profilePath, BuildPlan.SerializeProfile(Profile(["Microsoft.GetHelp"])));
            Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                profilePath,
                new HostComposeOptions(
                    iso,
                    WorkDirectory: Path.Combine(root, "work"),
                    WimIndex: 1),
                new RealHashProbe(),
                cancellationToken: TestContext.Current.CancellationToken);
            Assert.True(composed.IsOk);

            File.WriteAllBytes(profilePath, BuildPlan.SerializeProfile(Profile(["Microsoft.ZuneMusic"])));
            ImageServicingTestFakes.RecordingElevatedPlanRunner runner = new();
            Result<ImageEvidence, Failure> applied = await HostCompile.ApplyAsync(
                composed.Value,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(applied.IsOk, applied.IsOk ? null : applied.Error.Message);
            Assert.Contains("Microsoft.GetHelp", composed.Value.Review.RemoveProvisionedAppx);
            Assert.DoesNotContain("Microsoft.ZuneMusic", composed.Value.Review.RemoveProvisionedAppx);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task File_and_typed_composition_produce_equivalent_review_and_staged_artifacts()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            Profile profile = Profile(["Microsoft.GetHelp"]);
            string profilePath = Path.Combine(root, "same.profile.json");
            File.WriteAllBytes(profilePath, BuildPlan.SerializeProfile(profile));
            FixedTimeProvider time = new(new DateTimeOffset(2026, 8, 12, 12, 0, 0, TimeSpan.Zero));
            HostComposeOptions options = new(
                iso,
                ImageQualityLane.Release,
                Path.Combine(root, "work"),
                WimIndex: 1,
                ProfileName: profilePath);

            HostComposition typed = (await HostCompile.ComposeAsync(
                profile,
                options,
                new RealHashProbe(),
                time,
                TestContext.Current.CancellationToken)).Value;
            HostComposition file = (await HostCompile.ComposeFileAsync(
                profilePath,
                options,
                new RealHashProbe(),
                time,
                TestContext.Current.CancellationToken)).Value;

            Assert.Equal(typed.GetProfileUtf8(), file.GetProfileUtf8());
            Assert.Equal(typed.Review.ImageQuality, file.Review.ImageQuality);
            Assert.Equal(typed.Review.PackageStrict, file.Review.PackageStrict);
            Assert.Equal(
                typed.Review.SourceMedia!.SourceIsoSha256,
                file.Review.SourceMedia!.SourceIsoSha256);
            Assert.Equal(typed.Review.SourceMedia.Selected, file.Review.SourceMedia.Selected);
            Assert.Equal(typed.Review.SourceMedia.Indexes, file.Review.SourceMedia.Indexes);
            Assert.Equal(typed.Review.RemoveProvisionedAppx, file.Review.RemoveProvisionedAppx);
            Assert.Equal(typed.OutputIsoPath, file.OutputIsoPath);

            Assert.True((await HostCompile.ApplyAsync(
                typed,
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken)).IsOk);
            byte[] typedStages = File.ReadAllBytes(Path.Combine(typed.WorkDirectory, "stages.json"));
            Assert.True((await HostCompile.ApplyAsync(
                file,
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken)).IsOk);
            Assert.Equal(typedStages, File.ReadAllBytes(Path.Combine(file.WorkDirectory, "stages.json")));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static Profile Profile(IReadOnlyList<string> appx) =>
        new(
            new AccountProfile("winmint", "lab-only", false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            appx,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

    private static string NewRoot()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-composition-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static string WriteIso(string root)
    {
        string iso = Path.Combine(root, "source.iso");
        File.WriteAllText(iso, "iso-stub");
        return iso;
    }

    private sealed class FixedProbe : ISourceMediaProbe
    {
        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                Media(sourceIsoPath, wimIndex, new string('a', 64))));
    }

    private sealed class RealHashProbe : ISourceMediaProbe
    {
        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            string hash = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(sourceIsoPath)));
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(Media(sourceIsoPath, wimIndex, hash)));
        }
    }

    private sealed class ArchitectureProbe(string architecture) : ISourceMediaProbe
    {
        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            string hash = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(sourceIsoPath)));
            WimIndexInfo row = new(wimIndex, "Windows 11 Pro", architecture, "Professional", null, "26100");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new(
                    Path.GetFullPath(sourceIsoPath),
                    hash,
                    Array.AsReadOnly([row]),
                    new(wimIndex, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }

    private static SourceMediaReview Media(string iso, int index, string hash)
    {
        WimIndexInfo row = new(index, "Windows 11 Home", "ARM64", "Core", "10.0.26100.1", "26100");
        return new(
            Path.GetFullPath(iso),
            hash,
            Array.AsReadOnly([row]),
            new(index, row.Name, row.Architecture, row.Edition, row.Version, row.Build));
    }

    private sealed class CountingRunner : IElevatedPlanRunner
    {
        public int Calls { get; private set; }

        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            string workDirectory,
            CancellationToken ct)
        {
            Calls++;
            return Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset instant) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => instant;
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }
}
