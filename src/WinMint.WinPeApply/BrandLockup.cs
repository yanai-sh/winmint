using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using System.Text;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Direct2D;
using Windows.Win32.Graphics.Direct2D.Common;
using Windows.Win32.Graphics.Direct3D;
using Windows.Win32.Graphics.Direct3D11;
using Windows.Win32.Graphics.Dxgi;
using Windows.Win32.Graphics.Dxgi.Common;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.System.Com;

namespace WinMint.WinPeApply;

#pragma warning disable CA1416 // WinPE on a current Source ISO is Windows 10 or later.

/// <summary>
/// Paints <c>assets/brand/readme/dark.svg</c> — the icon and both wordmarks — through Direct2D.
/// <see cref="BrandMark"/> draws the solid icon when Direct2D cannot open the file.
/// </summary>
internal static class BrandLockup
{
    private const uint D3D11SdkVersion = 7;

    private static readonly Guid FactoryId = new("BB12D362-DAEE-4B9A-AA1D-14BA401CFA1F");
    private static readonly Guid DxgiDeviceId = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
    private static readonly Guid DeviceContext5Id = new("7836D248-68CC-4DF6-B9E8-DE991BF62EB7");

    private static readonly Lock Gate = new();
    private static byte[]? s_pixels;
    private static int s_width;
    private static int s_height;
    private static bool s_unavailable;

    internal static bool TryRasterize(int width, int height, out byte[] bgra)
    {
        bgra = [];
        if (width < 8 || height < 8)
        {
            return false;
        }

        lock (Gate)
        {
            if (s_unavailable)
            {
                return false;
            }

            if (s_pixels is not null && s_width == width && s_height == height)
            {
                bgra = s_pixels;
                return true;
            }

            try
            {
                bgra = Render(width, height);
                s_pixels = bgra;
                s_width = width;
                s_height = height;
                return true;
            }
            catch (Exception ex) when (ex is COMException
                or InvalidCastException
                or InvalidOperationException
                or DllNotFoundException
                or EntryPointNotFoundException
                or NullReferenceException
                or ArgumentException
                or NotSupportedException
                or PlatformNotSupportedException
                or OutOfMemoryException)
            {
                s_unavailable = true;
                bgra = [];
                return false;
            }
        }
    }

    /// <summary>Client-relative frame of the apply splash lockup.</summary>
    internal static bool TryFrame(int clientW, int clientH, out int x, out int y, out int width, out int height)
    {
        x = 0;
        y = 0;
        width = 0;
        height = 0;
        if (!TrySize(clientW, clientH, out width, out height))
        {
            return false;
        }

        x = (clientW - width) / 2;
        y = ((clientH - height) / 2) - (clientH / 18);
        if (y < 0)
        {
            y = 0;
        }

        return true;
    }

    internal static bool TryBlit(HDC hdc, RECT client, out int bottom)
    {
        bottom = 0;
        int clientW = client.right - client.left;
        int clientH = client.bottom - client.top;
        if (!TryFrame(clientW, clientH, out int frameX, out int frameY, out int width, out int height))
        {
            return false;
        }

        if (!TryRasterize(width, height, out byte[] pixels))
        {
            return false;
        }

        int x = client.left + frameX;
        int y = client.top + frameY;
        if (!Blit(hdc, x, y, width, height, pixels))
        {
            return false;
        }

        bottom = y + height;
        return true;
    }

    private static bool TrySize(int clientW, int clientH, out int width, out int height)
    {
        width = 0;
        height = 0;
        if (clientW < 320 || clientH < 200)
        {
            return false;
        }

        // viewBox 3048×762 is 4:1. Cap the lockup so the wordmark stays large and the progress row still fits.
        width = Math.Min(clientW * 62 / 100, 1680);
        height = width / 4;
        if (height > (clientH * 70 / 100))
        {
            height = clientH * 70 / 100;
            width = height * 4;
        }

        return width >= 64 && height >= 16;
    }

    private static unsafe byte[] Render(int width, int height)
    {
        ID2D1DeviceContext5 context = OpenContext();
        D2D1_BITMAP_PROPERTIES1 targetProps = Props(D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_TARGET);
        context.CreateBitmap(
            new D2D_SIZE_U { width = (uint)width, height = (uint)height },
            null,
            0,
            in targetProps,
            out ID2D1Bitmap1 target);
        context.SetTarget(target);

        byte[] svg = WithoutRootSize(BrandMark.EmbeddedSvg());
        IStream stream = PInvoke.SHCreateMemStream(svg) ?? throw new InvalidOperationException("SVG stream was not created.");
        context.CreateSvgDocument(
            stream,
            new D2D_SIZE_F { width = width, height = height },
            out ID2D1SvgDocument document);

        context.BeginDraw();
        try
        {
            context.Clear(new D2D1_COLOR_F { r = 0, g = 0, b = 0, a = 1 });
            context.DrawSvgDocument(document);
        }
        finally
        {
            HRESULT end = context.EndDraw();
            if (end.Failed)
            {
                Marshal.ThrowExceptionForHR(end);
            }
        }

        D2D1_BITMAP_PROPERTIES1 readProps = Props(
            D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_CANNOT_DRAW);
        context.CreateBitmap(
            new D2D_SIZE_U { width = (uint)width, height = (uint)height },
            null,
            0,
            in readProps,
            out ID2D1Bitmap1 readable);
        readable.CopyFromBitmap(null, target, null);
        readable.Map(D2D1_MAP_OPTIONS.D2D1_MAP_OPTIONS_READ, out D2D1_MAPPED_RECT mapped);
        try
        {
            return CopyMapped(mapped, width, height);
        }
        finally
        {
            readable.Unmap();
        }
    }

    private static ID2D1DeviceContext5 OpenContext()
    {
        HRESULT created = PInvoke.D2D1CreateFactory(
            D2D1_FACTORY_TYPE.D2D1_FACTORY_TYPE_SINGLE_THREADED,
            in FactoryId,
            null,
            out object factoryObject);
        if (created.Failed || factoryObject is not ID2D1Factory1 factory)
        {
            throw new InvalidOperationException("Direct2D factory was not created.");
        }

        if (!TryDevice(D3D_DRIVER_TYPE.D3D_DRIVER_TYPE_HARDWARE, out ID3D11Device? device)
            && !TryDevice(D3D_DRIVER_TYPE.D3D_DRIVER_TYPE_WARP, out device))
        {
            throw new InvalidOperationException("Direct3D device was not created.");
        }

        IDXGIDevice dxgi = Query<ID3D11Device, IDXGIDevice>(device!, DxgiDeviceId);
        factory.CreateDevice(dxgi, out ID2D1Device d2dDevice);
        d2dDevice.CreateDeviceContext(
            D2D1_DEVICE_CONTEXT_OPTIONS.D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
            out ID2D1DeviceContext deviceContext);
        return Query<ID2D1DeviceContext, ID2D1DeviceContext5>(deviceContext, DeviceContext5Id);
    }

    private static bool TryDevice(D3D_DRIVER_TYPE driver, out ID3D11Device? device)
    {
        HRESULT hr = PInvoke.D3D11CreateDevice(
            null!,
            driver,
            default,
            D3D11_CREATE_DEVICE_FLAG.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            [],
            D3D11SdkVersion,
            out ID3D11Device created,
            out ID3D11DeviceContext _);
        device = hr.Failed ? null : created;
        return hr.Succeeded;
    }

    private static unsafe TDest Query<TSource, TDest>(TSource source, Guid iid)
        where TSource : class
        where TDest : class
    {
        void* native = ComInterfaceMarshaller<TSource>.ConvertToUnmanaged(source);
        if (native is null)
        {
            throw new InvalidOperationException("COM unwrap failed.");
        }

        try
        {
            int hr = Marshal.QueryInterface((nint)native, in iid, out nint queried);
            if (hr < 0)
            {
                Marshal.ThrowExceptionForHR(hr);
            }

            try
            {
                return ComInterfaceMarshaller<TDest>.ConvertToManaged((void*)queried)
                    ?? throw new InvalidOperationException("COM wrap failed.");
            }
            finally
            {
                _ = Marshal.Release(queried);
            }
        }
        finally
        {
            _ = Marshal.Release((nint)native);
        }
    }

    private static D2D1_BITMAP_PROPERTIES1 Props(D2D1_BITMAP_OPTIONS options) => new()
    {
        pixelFormat = new D2D1_PIXEL_FORMAT
        {
            format = DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM,
            alphaMode = D2D1_ALPHA_MODE.D2D1_ALPHA_MODE_PREMULTIPLIED,
        },
        dpiX = 96,
        dpiY = 96,
        bitmapOptions = options,
    };

    private static unsafe byte[] CopyMapped(D2D1_MAPPED_RECT mapped, int width, int height)
    {
        int row = width * 4;
        byte[] pixels = new byte[row * height];
        for (int y = 0; y < height; y++)
        {
            Marshal.Copy((nint)(mapped.bits + (y * (int)mapped.pitch)), pixels, y * row, row);
        }

        return pixels;
    }

    /// <summary>
    /// Root width and height are the authoring canvas. Dropping them lets the viewBox fill the viewport we pass.
    /// </summary>
    private static byte[] WithoutRootSize(byte[] svg)
    {
        string text = Encoding.UTF8.GetString(svg);
        int start = text.IndexOf("<svg", StringComparison.Ordinal);
        int end = start < 0 ? -1 : text.IndexOf('>', start);
        if (start < 0 || end < 0)
        {
            return svg;
        }

        string open = text[start..end];
        open = RemoveAttr(open, "width");
        open = RemoveAttr(open, "height");
        return Encoding.UTF8.GetBytes(string.Concat(open, text.AsSpan(end)));
    }

    private static string RemoveAttr(string open, string name)
    {
        string key = " " + name + "=\"";
        int at = open.IndexOf(key, StringComparison.Ordinal);
        if (at < 0)
        {
            return open;
        }

        int valueEnd = open.IndexOf('"', at + key.Length);
        if (valueEnd < 0)
        {
            return open;
        }

        return string.Concat(open.AsSpan(0, at), open.AsSpan(valueEnd + 1));
    }

    private static unsafe bool Blit(HDC hdc, int x, int y, int width, int height, byte[] pixels)
    {
        if (pixels.Length < width * height * 4)
        {
            return false;
        }

        BITMAPINFO info = default;
        info.bmiHeader.biSize = (uint)sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        fixed (byte* bits = pixels)
        {
            int rows = PInvoke.SetDIBitsToDevice(
                hdc,
                x,
                y,
                (uint)width,
                (uint)height,
                0,
                0,
                0,
                (uint)height,
                bits,
                &info,
                DIB_USAGE.DIB_RGB_COLORS);
            return rows > 0;
        }
    }
}
