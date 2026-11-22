using System.Buffers.Binary;
using System.Text;

using Microsoft.Win32.SafeHandles;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Storage.FileSystem;

namespace WinMint.WinPeApply;

/// <summary>
/// Disk number and <c>STORAGE_BUS_TYPE</c>, the same property <c>Get-Disk</c> <c>BusType</c> reads.
/// </summary>
internal static class DiskBusList
{
    internal static string Render(IEnumerable<(int Disk, string Bus)> rows)
    {
        StringBuilder text = new();
        foreach ((int disk, string bus) in rows)
        {
            text.Append(disk);
            text.Append(' ');
            text.Append(bus);
            text.Append("\r\n");
        }

        return text.ToString();
    }

    internal static string Name(uint bus) => Name((STORAGE_BUS_TYPE)bus);

    internal static string Name(STORAGE_BUS_TYPE bus) => bus switch
    {
        STORAGE_BUS_TYPE.BusTypeUsb => "USB",
        STORAGE_BUS_TYPE.BusTypeSd => "SD",
        STORAGE_BUS_TYPE.BusTypeMmc => "MMC",
        STORAGE_BUS_TYPE.BusTypeVirtual => "Virtual",
        STORAGE_BUS_TYPE.BusTypeFileBackedVirtual => "FileBackedVirtual",
        STORAGE_BUS_TYPE.BusTypeNvme => "NVMe",
        STORAGE_BUS_TYPE.BusTypeSata => "SATA",
        STORAGE_BUS_TYPE.BusTypeScsi => "SCSI",
        STORAGE_BUS_TYPE.BusTypeRAID => "RAID",
        STORAGE_BUS_TYPE.BusTypeAta => "ATA",
        _ => "Other",
    };

    /// <summary>
    /// Every disk from 0 through the last one that opened. A hole or an empty scan is incomplete:
    /// LaunchApply refuses to format when this is false.
    /// </summary>
    internal static (bool Complete, List<(int Disk, string Bus)> Rows) Query()
    {
        List<(int Disk, string Bus)> rows = [];
        for (int disk = 0; disk < 32; disk++)
        {
            if (!TryQuery(disk, out string bus))
            {
                continue;
            }

            rows.Add((disk, bus));
        }

        return (IsComplete(rows), rows);
    }

    internal static bool IsComplete(IReadOnlyList<(int Disk, string Bus)> rows)
    {
        if (rows.Count == 0)
        {
            return false;
        }

        for (int i = 0; i < rows.Count; i++)
        {
            if (rows[i].Disk != i)
            {
                return false;
            }
        }

        return true;
    }

    private static unsafe bool TryQuery(int disk, out string bus)
    {
        bus = "";
        SafeFileHandle handle = PInvoke.CreateFile(
            $@"\\.\PhysicalDrive{disk}",
            (uint)GENERIC_ACCESS_RIGHTS.GENERIC_READ,
            FILE_SHARE_MODE.FILE_SHARE_READ | FILE_SHARE_MODE.FILE_SHARE_WRITE,
            lpSecurityAttributes: null,
            FILE_CREATION_DISPOSITION.OPEN_EXISTING,
            FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
            hTemplateFile: null);
        if (handle.IsInvalid)
        {
            handle.Dispose();
            return false;
        }

        try
        {
            // StorageDeviceProperty + PropertyStandardQuery. Both values are 0.
            Span<byte> input = stackalloc byte[8];
            Span<byte> output = stackalloc byte[512];
            if (!PInvoke.DeviceIoControl(handle, PInvoke.IOCTL_STORAGE_QUERY_PROPERTY, input, output, out uint returned))
            {
                return false;
            }

            // STORAGE_DEVICE_DESCRIPTOR.BusType is the uint at offset 28.
            if (returned < 32)
            {
                return false;
            }

            bus = Name(BinaryPrimitives.ReadUInt32LittleEndian(output.Slice(28, 4)));
            return true;
        }
        finally
        {
            handle.Dispose();
        }
    }
}
