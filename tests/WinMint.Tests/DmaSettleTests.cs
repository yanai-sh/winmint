using WinMint.Provisioning;
using WinMint.Contracts;
using DmaSettleTarget = WinMint.Contracts.DmaSettleTarget;
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

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, evidence, processes, winlogon),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("settle.hardMismatch", result.FinalStatus.Code);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:jobs.", StringComparison.Ordinal));
        Assert.Empty(processes.Starts);
        Assert.Single(region.Applied);
        Assert.Equal(242, region.Applied[0].GeoId);
        Assert.Contains("settle.hardMismatch", evidence.Documents[0].Phases);
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

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.Contains("Status:settle.deviceRegionOk", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.hardMismatch", StringComparison.Ordinal));
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.readFailed", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Shell_soft_location_mismatch_warns_and_continues()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", false)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
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
        Assert.Contains("Status:settle.deviceRegionOk", splash.Events);
        Assert.Contains("Status:settle.locationWarn", splash.Events);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.Contains("settle.locationWarn", evidence.Documents[0].Phases);
        Assert.Contains("settle.deviceRegionOk", evidence.Documents[0].Phases);
        Assert.Equal("Complete", evidence.Documents[0].Outcome);
    }

    [Fact]
    public async Task Shell_dma_disabled_skips_settle_without_region_apply()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new();
        RecordingSplashPresenter splash = new();
        OkDmaSetupRegion dmaSetup = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(dma: new DmaSettleTarget(Enabled: false, null, null, null, null)),
            Env(time, region, splash, new RecordingEvidenceSink(), dmaSetup: dmaSetup),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Empty(region.Applied);
        Assert.Equal(0, dmaSetup.EnsureCalls);
        Assert.Contains("Status:settle.skipped", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.deviceRegion", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Shell_repairs_device_region_then_completes()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        ScriptedDmaSetupRegion dmaSetup = new(ScriptedDmaSetupRegion.DmaSetupStep.Repaired);

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, evidence, dmaSetup: dmaSetup),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, dmaSetup.EnsureCalls);
        Assert.Contains("Status:settle.deviceRegionRepaired", splash.Events);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.Contains("settle.deviceRegionRepaired", evidence.Documents[0].Phases);
    }

    [Fact]
    public async Task Shell_device_region_irreparable_fails_and_skips_jobs()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        RecordingProcessHost processes = new();
        ScriptedDmaSetupRegion dmaSetup = new(
            ScriptedDmaSetupRegion.DmaSetupStep.Throw("DeviceRegion verify failed"));

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, evidence, processes, dmaSetup: dmaSetup),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("settle.deviceRegionFailed", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
        Assert.Contains("settle.deviceRegionFailed", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.begin", evidence.Documents[0].Phases);
    }

    [Fact]
    public async Task Shell_settle_target_missing_locationServices_fails_before_region_apply()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", null)),
            Env(time, region, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("settle.targetIncomplete", result.FinalStatus.Code);
        Assert.Empty(region.Applied);
        Assert.Contains("settle.targetIncomplete", evidence.Documents[0].Phases);
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

    private static ShellEnvironment Env(
        TimeProvider time,
        IRegionSnapshot region,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IProcessHost? processes = null,
        IWinlogonRegistry? winlogon = null,
        IDmaSetupRegion? dmaSetup = null) =>
        ProvisioningSessionTestFakes.Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon ?? new NoopWinlogon(),
                Region = region,
                Processes = processes ?? new RecordingProcessHost(),
                DmaSetup = dmaSetup ?? new OkDmaSetupRegion(),
            },
            evidence,
            time,
            splash);

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
