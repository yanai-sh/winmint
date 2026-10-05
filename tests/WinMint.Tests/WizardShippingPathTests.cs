using WinMint.Orchestrator;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class WizardShippingPathTests
{
    [Fact]
    public void Wizard_draft_compose_options_are_shipping_gate_b()
    {
        using WizardViewModel vm = new(storage: null, close: null, sourceMedia: null);
        vm.Source.SourceIsoPath = @"C:\iso\source.iso";

        Result<WizardDraft, Failure> draft = vm.BuildDraft();

        Assert.True(draft.IsOk);
        HostComposeOptions options = draft.Value.Options;
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
