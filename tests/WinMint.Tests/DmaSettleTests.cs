using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class DmaSettleTests
{
    [Fact]
    public async Task Shell_final_hard_GeoId_mismatch_fails_and_skips_jobs()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-IE", 68, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        RecordingProcessHost processes = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, evidence, processes, winlogon),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("settle.hard_mismatch", result.FinalStatus.Code);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:jobs.", StringComparison.Ordinal));
        Assert.Empty(processes.Starts);
        Assert.Single(region.Applied);
        Assert.Equal(242, region.Applied[0].GeoId);
        Assert.Contains("settle.hard_mismatch", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.begin", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public async Task Shell_intermediate_probe_failures_are_non_authoritative()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ThrowRead("transient DMA probe"),
            new RegionRead.ThrowRead("still settling"),
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.hard_mismatch", StringComparison.Ordinal));
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.read_failed", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Shell_soft_location_mismatch_warns_and_continues()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", false)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.Zero,
                    SettlePollInterval = TimeSpan.Zero,
                }),
            Env(time, region, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.location_warn", splash.Events);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.Contains("settle.location_warn", evidence.Documents[0].Phases);
        Assert.Equal("Complete", evidence.Documents[0].Outcome);
    }

    [Fact]
    public async Task Shell_dma_disabled_skips_settle_without_region_apply()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new();
        RecordingSplashPresenter splash = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(dma: new DmaSettleTarget(Enabled: false, null, null, null, null)),
            Env(time, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Empty(region.Applied);
        Assert.Contains("Status:settle.skipped", splash.Events);
    }

    private static SessionPolicy TightSettlePolicy() =>
        SessionPolicy.SmokeDefaults with
        {
            SettleDeadline = TimeSpan.FromSeconds(4),
            SettlePollInterval = TimeSpan.FromSeconds(2),
        };

    private static ProvisioningBundle Bundle(DmaSettleTarget dma, SessionPolicy? policy = null) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: dma,
            Jobs: [new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub)],
            Policy: policy ?? TightSettlePolicy(),
            SupervisorShellPath: SupervisorPath);

    private static SessionEnvironment Env(
        TimeProvider time,
        IRegionSnapshot region,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IProcessHost? processes = null,
        IWinlogonRegistry? winlogon = null) =>
        new(
            Time: time,
            Winlogon: winlogon ?? new NoopWinlogon(),
            Region: region,
            Processes: processes ?? new RecordingProcessHost(),
            Splash: splash,
            Checkpoints: new NoopCheckpoints(),
            Evidence: evidence);

    private abstract record RegionRead
    {
        public sealed record ValueRead(RegionState State) : RegionRead;

        public sealed record ThrowRead(string Message) : RegionRead;
    }

    private sealed class ScriptedRegionSnapshot : IRegionSnapshot
    {
        private readonly Queue<RegionRead> _reads;
        private RegionState? _lastGood;

        public ScriptedRegionSnapshot(params RegionRead[] reads) =>
            _reads = new Queue<RegionRead>(reads);

        public List<DmaSettleTarget> Applied { get; } = [];

        public void Apply(DmaSettleTarget target) => Applied.Add(target);

        public RegionState Read()
        {
            if (_reads.Count > 0)
            {
                return _reads.Dequeue() switch
                {
                    RegionRead.ValueRead v => _lastGood = v.State,
                    RegionRead.ThrowRead t => throw new InvalidOperationException(t.Message),
                    _ => throw new InvalidOperationException("Unknown scripted read."),
                };
            }

            // Sticky last probe — models OS state for the post-poll final snapshot Read.
            return _lastGood
                ?? throw new InvalidOperationException("No scripted region reads left.");
        }
    }
}
