using WinMint.Orchestrator;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class WizardShippingPathTests
{
    [Fact]
    public void Wizard_BuildDraft_delegates_to_shipping_compile()
    {
        using WizardViewModel vm = new(storage: null, close: null, sourceMedia: null);
        vm.Source.SourceIsoPath = @"C:\iso\source.iso";

        Result<WizardDraft, Failure> draft = vm.BuildDraft();

        Assert.True(draft.IsOk);
        Assert.Equal(ImageQualityLane.Release, draft.Value.Options.ImageQuality);
        Assert.Equal(PackageStrictOverride.FromLane, draft.Value.Options.PackageStrict);
    }

    [Fact]
    public void Source_stage_has_no_lane_selection_surface()
    {
        Assert.Null(typeof(ISourceStageViewModel).GetProperty("Lane"));
        Assert.Null(typeof(ISourceStageViewModel).GetProperty("SelectLaneCommand"));
    }
}
