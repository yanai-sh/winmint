using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

/// <summary>The wizard's own coordination, reachable now that the host is a picker and a close action.</summary>
public class WizardViewModelTests
{
    [Fact]
    public void Replan_reports_an_unknown_chip_key_as_status_instead_of_throwing()
    {
        using WizardViewModel vm = Vm();
        vm.BrowserChips.Add(new ChipItem("not-in-catalog", "Nope", isSelected: true));

        vm.ReplanCommand.Execute(null);

        Assert.True(vm.StatusIsError);
        Assert.Contains("packages.catalog.unknown", vm.Status, StringComparison.Ordinal);
        Assert.Contains("not-in-catalog", vm.Status, StringComparison.Ordinal);
    }

    [Fact]
    public void Close_without_a_host_window_is_a_no_op()
    {
        using WizardViewModel vm = Vm();

        vm.CloseCommand.Execute(null);
    }

    private static WizardViewModel Vm() => new(storage: null, close: null, wimIndexSource: null);
}
