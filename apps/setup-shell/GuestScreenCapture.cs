using System.IO.Compression;
using System.Runtime.InteropServices;

namespace WinMintSetupShell;

internal static class GuestScreenCapture
{
    private const uint PwRenderFullContent = 2;
    private const uint BiRgb = 0;

    public static bool TryCaptureWindow(nint hwnd, string outputPath)
    {
        if (hwnd == nint.Zero)
        {
            return false;
        }

        NativeMethods.GetClientRect(hwnd, out var rect);
        var width = rect.Width;
        var height = rect.Height;
        if (width < 64 || height < 64)
        {
            return false;
        }

        nint hdcScreen = nint.Zero;
        nint hdcMem = nint.Zero;
        nint hBitmap = nint.Zero;
        nint oldBitmap = nint.Zero;

        try
        {
            hdcScreen = GetDC(hwnd);
            if (hdcScreen == nint.Zero)
            {
                return false;
            }

            hdcMem = CreateCompatibleDC(hdcScreen);
            hBitmap = CreateCompatibleBitmap(hdcScreen, width, height);
            if (hdcMem == nint.Zero || hBitmap == nint.Zero)
            {
                return false;
            }

            oldBitmap = SelectObject(hdcMem, hBitmap);
            if (!PrintWindow(hwnd, hdcMem, PwRenderFullContent))
            {
                PrintWindow(hwnd, hdcMem, 0);
            }

            var info = new BitmapInfo
            {
                Header = new BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                    Width = width,
                    Height = -height,
                    Planes = 1,
                    BitCount = 32,
                    Compression = BiRgb
                }
            };

            var stride = width * 4;
            var pixels = new byte[stride * height];
            if (GetDIBits(hdcMem, hBitmap, 0, (uint)height, pixels, ref info, 0) == 0)
            {
                return false;
            }

            var dir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            WritePngBgra32(outputPath, pixels, width, height, stride);
            return File.Exists(outputPath) && new FileInfo(outputPath).Length >= 8192;
        }
        catch
        {
            return false;
        }
        finally
        {
            if (oldBitmap != nint.Zero && hdcMem != nint.Zero)
            {
                SelectObject(hdcMem, oldBitmap);
            }
            if (hBitmap != nint.Zero)
            {
                DeleteObject(hBitmap);
            }
            if (hdcMem != nint.Zero)
            {
                DeleteDC(hdcMem);
            }
            if (hdcScreen != nint.Zero)
            {
                ReleaseDC(hwnd, hdcScreen);
            }
        }
    }

    internal static void WritePngBgra32(string path, byte[] pixels, int width, int height, int stride)
    {
        using var raw = new MemoryStream();
        for (var y = 0; y < height; y++)
        {
            raw.WriteByte(0);
            var rowStart = y * stride;
            for (var x = 0; x < width; x++)
            {
                var i = rowStart + (x * 4);
                var b = pixels[i];
                var g = pixels[i + 1];
                var r = pixels[i + 2];
                var a = pixels[i + 3];
                if (a > 0 && a < 255)
                {
                    r = (byte)Math.Min(255, (r * 255) / a);
                    g = (byte)Math.Min(255, (g * 255) / a);
                    b = (byte)Math.Min(255, (b * 255) / a);
                }
                else if (a == 0)
                {
                    r = g = b = 0;
                }

                raw.WriteByte(r);
                raw.WriteByte(g);
                raw.WriteByte(b);
            }
        }

        var compressed = CompressZlib(raw.ToArray());
        using var output = File.Open(path, FileMode.Create, FileAccess.Write, FileShare.Read);
        output.Write([137, 80, 78, 71, 13, 10, 26, 10]);
        WritePngChunk(output, "IHDR", BuildIhdr(width, height));
        WritePngChunk(output, "IDAT", compressed);
        WritePngChunk(output, "IEND", []);
    }

    private static byte[] BuildIhdr(int width, int height)
    {
        var data = new byte[13];
        WriteUInt32Be(data, 0, (uint)width);
        WriteUInt32Be(data, 4, (uint)height);
        data[8] = 8;
        data[9] = 2;
        data[10] = 0;
        data[11] = 0;
        data[12] = 0;
        return data;
    }

    private static byte[] CompressZlib(byte[] input)
    {
        using var output = new MemoryStream();
        output.WriteByte(0x78);
        output.WriteByte(0x01);
        using (var deflate = new ZLibStream(output, CompressionLevel.Fastest, leaveOpen: true))
        {
            deflate.Write(input, 0, input.Length);
        }

        var adler = Adler32(input);
        output.WriteByte((byte)((adler >> 24) & 0xFF));
        output.WriteByte((byte)((adler >> 16) & 0xFF));
        output.WriteByte((byte)((adler >> 8) & 0xFF));
        output.WriteByte((byte)(adler & 0xFF));
        return output.ToArray();
    }

    private static uint Adler32(ReadOnlySpan<byte> data)
    {
        const uint mod = 65521;
        uint a = 1;
        uint b = 0;
        foreach (var value in data)
        {
            a = (a + value) % mod;
            b = (b + a) % mod;
        }

        return (b << 16) | a;
    }

    private static void WritePngChunk(Stream stream, string type, byte[] data)
    {
        var typeBytes = System.Text.Encoding.ASCII.GetBytes(type);
        WriteUInt32Be(stream, (uint)data.Length);
        stream.Write(typeBytes, 0, typeBytes.Length);
        stream.Write(data, 0, data.Length);
        var crcInput = new byte[typeBytes.Length + data.Length];
        Buffer.BlockCopy(typeBytes, 0, crcInput, 0, typeBytes.Length);
        Buffer.BlockCopy(data, 0, crcInput, typeBytes.Length, data.Length);
        WriteUInt32Be(stream, Crc32(crcInput));
    }

    private static void WriteUInt32Be(byte[] buffer, int offset, uint value)
    {
        buffer[offset] = (byte)((value >> 24) & 0xFF);
        buffer[offset + 1] = (byte)((value >> 16) & 0xFF);
        buffer[offset + 2] = (byte)((value >> 8) & 0xFF);
        buffer[offset + 3] = (byte)(value & 0xFF);
    }

    private static void WriteUInt32Be(Stream stream, uint value)
    {
        Span<byte> buffer = stackalloc byte[4];
        buffer[0] = (byte)((value >> 24) & 0xFF);
        buffer[1] = (byte)((value >> 16) & 0xFF);
        buffer[2] = (byte)((value >> 8) & 0xFF);
        buffer[3] = (byte)(value & 0xFF);
        stream.Write(buffer);
    }

    private static uint Crc32(ReadOnlySpan<byte> data)
    {
        uint crc = 0xFFFFFFFF;
        foreach (var value in data)
        {
            crc ^= value;
            for (var i = 0; i < 8; i++)
            {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
            }
        }

        return crc ^ 0xFFFFFFFF;
    }

    [DllImport("user32.dll")]
    private static extern nint GetDC(nint hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(nint hWnd, nint hDC);

    [DllImport("user32.dll")]
    private static extern bool PrintWindow(nint hwnd, nint hdcBlt, uint nFlags);

    [DllImport("gdi32.dll")]
    private static extern nint CreateCompatibleDC(nint hdc);

    [DllImport("gdi32.dll")]
    private static extern nint CreateCompatibleBitmap(nint hdc, int width, int height);

    [DllImport("gdi32.dll")]
    private static extern nint SelectObject(nint hdc, nint hgdiobj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(nint hObject);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(nint hdc);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(
        nint hdc,
        nint hbmp,
        uint uStartScan,
        uint cScanLines,
        byte[] lpvBits,
        ref BitmapInfo lpbi,
        uint uUsage);

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ClrUsed;
        public uint ClrImportant;
    }
}
