using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class DmaSetupRegionLatchTests
{
    [Fact]
    public void MachineSetup_access_denied_is_soft()
    {
        ScriptedDmaSetupRegion port = new(ScriptedDmaSetupRegion.DmaSetupStep.ThrowUnauthorized);
        DmaSetupRegionLatch latch = ProvisioningSession.EnsureDmaSetupRegion(
            port,
            DmaSetupRegionPolicy.MachineSetup);
        Assert.Equal(DmaSetupRegionLatchKind.AccessDeniedSoft, latch.Kind);
    }

    [Fact]
    public void Settle_access_denied_is_hard_fail()
    {
        ScriptedDmaSetupRegion port = new(ScriptedDmaSetupRegion.DmaSetupStep.ThrowUnauthorized);
        DmaSetupRegionLatch latch = ProvisioningSession.EnsureDmaSetupRegion(
            port,
            DmaSetupRegionPolicy.Settle);
        Assert.Equal(DmaSetupRegionLatchKind.Failed, latch.Kind);
    }

    [Fact]
    public void Settle_repaired_is_ok()
    {
        ScriptedDmaSetupRegion port = new(ScriptedDmaSetupRegion.DmaSetupStep.Repaired);
        DmaSetupRegionLatch latch = ProvisioningSession.EnsureDmaSetupRegion(
            port,
            DmaSetupRegionPolicy.Settle);
        Assert.Equal(DmaSetupRegionLatchKind.Ok, latch.Kind);
        Assert.Equal(DmaSetupRegionEnsureResult.Repaired, latch.EnsureResult);
    }

    [Fact]
    public void Missing_port_is_missing()
    {
        DmaSetupRegionLatch latch = ProvisioningSession.EnsureDmaSetupRegion(
            null,
            DmaSetupRegionPolicy.Settle);
        Assert.Equal(DmaSetupRegionLatchKind.MissingPort, latch.Kind);
    }
}
