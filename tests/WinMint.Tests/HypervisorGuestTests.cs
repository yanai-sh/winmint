using WinMint.Provisioning;

namespace WinMint.Tests;

public class HypervisorGuestTests
{
    [Fact]
    public void HyperV_virtual_machine_is_guest()
    {
        Assert.True(HypervisorGuest.IsGuest("Microsoft Corporation", "Virtual Machine", hyperVGuestKeyExists: false));
    }

    [Fact]
    public void Sl7_host_desktop_is_not_guest_even_if_caller_might_see_hypervisor()
    {
        Assert.False(HypervisorGuest.IsGuest("Microsoft Corporation", "Surface Laptop 7", hyperVGuestKeyExists: false));
    }

    [Fact]
    public void HyperV_guest_key_alone_is_guest()
    {
        Assert.True(HypervisorGuest.IsGuest("Unknown", "Unknown", hyperVGuestKeyExists: true));
    }
}
