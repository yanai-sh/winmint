using WinMint.WinPeApply;

namespace WinMint.Tests;

public class DiskBusListTests
{
    [Fact]
    public void Name_maps_the_buses_the_installer_skips()
    {
        Assert.Equal("USB", DiskBusList.Name(7));
        Assert.Equal("SD", DiskBusList.Name(12));
        Assert.Equal("MMC", DiskBusList.Name(13));
        Assert.Equal("Virtual", DiskBusList.Name(14));
        Assert.Equal("FileBackedVirtual", DiskBusList.Name(15));
        Assert.Equal("NVMe", DiskBusList.Name(17));
    }

    [Fact]
    public void IsComplete_rejects_an_empty_scan_and_a_hole()
    {
        Assert.False(DiskBusList.IsComplete([]));
        Assert.True(DiskBusList.IsComplete([(0, "NVMe")]));
        Assert.True(DiskBusList.IsComplete([(0, "USB"), (1, "NVMe")]));
        Assert.False(DiskBusList.IsComplete([(0, "NVMe"), (2, "USB")]));
        Assert.False(DiskBusList.IsComplete([(1, "NVMe")]));
    }

    [Fact]
    public void Render_prints_disk_number_and_bus_name()
    {
        string text = DiskBusList.Render([(0, "USB"), (1, "NVMe")]);
        Assert.Equal("0 USB\r\n1 NVMe\r\n", text);
    }
}
