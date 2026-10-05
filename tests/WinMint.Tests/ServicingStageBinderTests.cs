using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ServicingStageBinderTests
{
    [Fact]
    public void WithQualityUpdateOpcode_inserts_before_patch_boot_wim()
    {
        List<ServicingOpcode> bound = ImageServicing.WithQualityUpdateOpcode(
        [
            ServicingOpcode.MountInstallWim,
            ServicingOpcode.PatchBootWimApply,
            ServicingOpcode.ExportWim,
        ]);

        Assert.Equal(
            [
                ServicingOpcode.MountInstallWim,
                ServicingOpcode.AddQualityUpdates,
                ServicingOpcode.PatchBootWimApply,
                ServicingOpcode.ExportWim,
            ],
            bound);
    }

    [Fact]
    public void WithQualityUpdateOpcode_is_idempotent()
    {
        List<ServicingOpcode> once = ImageServicing.WithQualityUpdateOpcode(
        [
            ServicingOpcode.AddQualityUpdates,
            ServicingOpcode.PatchBootWimApply,
        ]);
        List<ServicingOpcode> twice = ImageServicing.WithQualityUpdateOpcode(once);
        Assert.Equal(once, twice);
        Assert.Equal(1, twice.Count(o => o == ServicingOpcode.AddQualityUpdates));
    }

    [Fact]
    public void WithQualityUpdateOpcode_skips_when_no_boot_patch()
    {
        List<ServicingOpcode> bound = ImageServicing.WithQualityUpdateOpcode(
        [
            ServicingOpcode.MountInstallWim,
            ServicingOpcode.BuildIso,
        ]);
        Assert.DoesNotContain(ServicingOpcode.AddQualityUpdates, bound);
    }
}
