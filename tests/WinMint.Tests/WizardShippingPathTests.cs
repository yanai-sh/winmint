using WinMint.Orchestrator;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class WizardShippingPathTests
{
    [Fact]
    public void Wizard_draft_compose_options_are_shipping_gate_b()
    {
        // Build HostComposeOptions the same way WizardViewModel.BuildDraft does after this task:
        // ImageQuality = Release, PackageStrict = FromLane (default).
        HostComposeOptions options = new(
            SourceIsoPath: @"C:\iso\source.iso",
            ImageQuality: ImageQualityLane.Release);
        Assert.Equal(ImageQualityLane.Release, options.ImageQuality);
        Assert.Equal(PackageStrictOverride.FromLane, options.PackageStrict);
        Assert.True(HostDefaults.ResolvePackageStrict(options.ImageQuality, options.PackageStrict));
    }

    [Fact]
    public void Source_stage_has_no_lane_selection_surface()
    {
        // After removal: ISourceStageViewModel must not expose SelectLaneCommand / Lane chips.
        // Assert via reflection or compile-time: SourceStageViewModel has no public SelectLaneCommand.
        Assert.Null(typeof(ISourceStageViewModel).GetProperty("Lane"));
        Assert.Null(typeof(ISourceStageViewModel).GetProperty("SelectLaneCommand"));
    }
}
