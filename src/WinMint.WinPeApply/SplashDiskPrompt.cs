using System.Globalization;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace WinMint.WinPeApply;

/// <summary>
/// Centered disk lines under the large lockup. A frame shows the focused row.
/// The line under the lockup says how Enter marks it. There is no second control.
/// </summary>
internal static class SplashDiskPrompt
{
    internal const string Heading = "Target disk";
    internal const string Lead = "Nothing is selected. Press the arrow keys.";
    internal const int HeroGap = 16;

    internal static int PromptTop(int heroBottom, int dpi) => heroBottom + Px(HeroGap, dpi);

    internal static string Fact(int count)
    {
        if (count == 0)
        {
            return "No disk was listed.";
        }

        if (count == 1)
        {
            return "1 disk listed.";
        }

        return string.Create(CultureInfo.InvariantCulture, $"{count} disks listed.");
    }

    internal static string Marked(SplashDisk disk) => Name(disk) + " is marked. The disk was not erased.";

    internal static string Cue(SplashDisk disk) => "Press Enter to mark " + Name(disk) + ". The disk is not erased.";

    private static string Name(SplashDisk disk)
    {
        return string.IsNullOrWhiteSpace(disk.Model)
            ? string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}, {disk.Size}")
            : string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}, {disk.Size}, {disk.Model}");
    }

    internal readonly record struct Box(int X, int Y, int W, int H)
    {
        internal int Right => X + W;

        internal int Bottom => Y + H;
    }

    internal readonly record struct PromptLayout(
        int Margin,
        Box Mark,
        Box Status,
        Box List,
        int RowHeight,
        int RowGap);

    internal static int Px(int px, int dpi) => Math.Max(1, px * Math.Max(dpi, 96) / 96);

    internal static string RowLabel(SplashDisk disk)
    {
        string core = string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}  {disk.Size}");
        return string.IsNullOrWhiteSpace(disk.Model)
            ? core
            : string.Create(CultureInfo.InvariantCulture, $"{core}  {disk.Model}");
    }

    internal static PromptLayout Measure(int width, int height, int dpi, int rows, int minY = 0, string? status = null)
    {
        width = Math.Max(width, 1);
        height = Math.Max(height, 1);
        rows = Math.Max(rows, 0);
        int gutter = width < Px(640, dpi) ? Px(24, dpi) : Px(80, dpi);
        int column = Math.Min(Px(560, dpi), Math.Max(Px(240, dpi), width - (2 * gutter)));
        int margin = Math.Max(0, (width - column) / 2);
        int origin = Math.Max(0, minY);
        int limit = Math.Max(height, 1) - Px(24, dpi);
        string statusText = string.IsNullOrEmpty(status) ? Lead : status;
        int statusLines = Lines(statusText, column, dpi);
        int rowH = Px(40, dpi);
        int rowGap = rows > 1 ? Px(8, dpi) : 0;
        Box statusBox = new(margin, origin, column, Px(24, dpi) * statusLines);
        int listY = statusBox.Bottom + Px(12, dpi);
        int listH = rows == 0 ? 0 : (rows * rowH) + ((rows - 1) * rowGap);
        if (rows > 0 && (listY + listH) > limit && statusLines > 1)
        {
            statusLines = 1;
            statusBox = new(margin, origin, column, Px(24, dpi));
            listY = statusBox.Bottom + Px(12, dpi);
        }

        Box list = new(margin, listY, column, listH);
        return new PromptLayout(margin, default, statusBox, list, rowH, rowGap);
    }

    private static int Lines(string text, int column, int dpi)
    {
        int perLine = Math.Max(8, column / Px(9, dpi));
        return Math.Clamp((text.Length + perLine - 1) / perLine, 1, 4);
    }
}

internal sealed class SplashPromptPainter : IDisposable
{
    private const int RadiusPx = 4;

    private static readonly COLORREF Ink = new(0x00FBF7F3);
    private static readonly COLORREF Mint = new(0x008CD04C);
    private static readonly COLORREF Hair = new(0x005C5C5C);
    private static readonly COLORREF Ground = new(0x00000000);

    private HFONT _body;
    private int _dpi = 96;
    private bool _ready;

    internal void Paint(HDC hdc, RECT client, int dpi, IReadOnlyList<SplashDisk> disks, int focus, int marked)
    {
        int width = client.right - client.left;
        int height = client.bottom - client.top;
        int minY = HeroBand(hdc, client, dpi);
        string status = Status(disks, focus, marked);
        SplashDiskPrompt.PromptLayout layout = SplashDiskPrompt.Measure(width, height, dpi, disks.Count, minY, status);
        EnsureFonts(dpi);
        Text(hdc, _body, Ink, status, client, layout.Status, wrap: true, center: true);

        for (int i = 0; i < disks.Count; i++)
        {
            DrawRow(hdc, client, layout, disks[i], i, focused: i == focus);
        }
    }

    public void Dispose() => FreeFonts();

    private static string Status(IReadOnlyList<SplashDisk> disks, int focus, int marked)
    {
        if (marked >= 0 && marked < disks.Count)
        {
            return SplashDiskPrompt.Marked(disks[marked]);
        }

        if (focus >= 0 && focus < disks.Count)
        {
            return SplashDiskPrompt.Cue(disks[focus]);
        }

        return disks.Count == 0 ? SplashDiskPrompt.Fact(0) : SplashDiskPrompt.Lead;
    }

    private void DrawRow(HDC hdc, RECT client, SplashDiskPrompt.PromptLayout layout, SplashDisk disk, int index, bool focused)
    {
        int y = client.top + layout.List.Y + (index * (layout.RowHeight + layout.RowGap));
        int x = client.left + layout.List.X;
        if (focused)
        {
            Frame(hdc, x, y, layout.List.W, layout.RowHeight);
        }
        else
        {
            Hairline(hdc, x, y + layout.RowHeight - 1, x + layout.List.W);
        }

        Text(
            hdc,
            _body,
            focused ? Mint : Ink,
            SplashDiskPrompt.RowLabel(disk),
            default,
            new SplashDiskPrompt.Box(x, y, layout.List.W, layout.RowHeight),
            wrap: false,
            absolute: true,
            center: true);
    }

    private void Frame(HDC hdc, int x, int y, int w, int h)
    {
        int corner = Math.Max(2, SplashDiskPrompt.Px(RadiusPx, _dpi) * 2);
        HBRUSH brush = PInvoke.CreateSolidBrush(Ground);
        int weight = Math.Max(1, SplashDiskPrompt.Px(2, _dpi));
        HPEN pen = PInvoke.CreatePen(PEN_STYLE.PS_SOLID, weight, Mint);
        HGDIOBJ oldBrush = PInvoke.SelectObject(hdc, brush);
        HGDIOBJ oldPen = PInvoke.SelectObject(hdc, pen);
        _ = PInvoke.RoundRect(hdc, x, y, x + w, y + h, corner, corner);
        _ = PInvoke.SelectObject(hdc, oldBrush);
        _ = PInvoke.SelectObject(hdc, oldPen);
        _ = PInvoke.DeleteObject(brush);
        _ = PInvoke.DeleteObject(pen);
    }

    private static void Hairline(HDC hdc, int x0, int y, int x1)
    {
        HPEN pen = PInvoke.CreatePen(PEN_STYLE.PS_SOLID, 1, Hair);
        HGDIOBJ old = PInvoke.SelectObject(hdc, pen);
        unsafe
        {
            _ = PInvoke.MoveToEx(hdc, x0, y, null);
            _ = PInvoke.LineTo(hdc, x1, y);
        }

        _ = PInvoke.SelectObject(hdc, old);
        _ = PInvoke.DeleteObject(pen);
    }

    private static int HeroBand(HDC hdc, RECT client, int dpi)
    {
        if (BrandLockup.TryBlit(hdc, client, out int bottom))
        {
            return SplashDiskPrompt.PromptTop(bottom - client.top, dpi);
        }

        // Same fallback placement as the apply splash: the icon, then the progress row.
        int cy = (client.top + client.bottom) / 2;
        BrandMark.Draw(hdc, (client.left + client.right) / 2, cy - 28);
        return (cy + 78) - client.top;
    }

    private void EnsureFonts(int dpi)
    {
        if (_ready && _dpi == dpi)
        {
            return;
        }

        FreeFonts();
        _dpi = Math.Max(dpi, 96);
        _body = Font(SplashDiskPrompt.Px(16, _dpi), 400);
        _ready = !_body.IsNull;
    }

    private static HFONT Font(int height, int weight)
    {
        unsafe
        {
            fixed (char* face = "Segoe UI")
            {
                return PInvoke.CreateFont(
                    -height,
                    0,
                    0,
                    0,
                    weight,
                    0,
                    0,
                    0,
                    FONT_CHARSET.DEFAULT_CHARSET,
                    FONT_OUTPUT_PRECISION.OUT_DEFAULT_PRECIS,
                    FONT_CLIP_PRECISION.CLIP_DEFAULT_PRECIS,
                    FONT_QUALITY.CLEARTYPE_QUALITY,
                    0,
                    face);
            }
        }
    }

    private void FreeFonts()
    {
        Drop(ref _body);
        _ready = false;
    }

    private static void Drop(ref HFONT font)
    {
        if (!font.IsNull)
        {
            _ = PInvoke.DeleteObject(font);
            font = default;
        }
    }

    private static void Text(
        HDC hdc,
        HFONT font,
        COLORREF color,
        string text,
        RECT client,
        SplashDiskPrompt.Box box,
        bool wrap,
        bool absolute = false,
        bool center = false)
    {
        if (font.IsNull || text.Length == 0)
        {
            return;
        }

        int x = absolute ? box.X : client.left + box.X;
        int y = absolute ? box.Y : client.top + box.Y;
        HGDIOBJ old = PInvoke.SelectObject(hdc, font);
        _ = PInvoke.SetBkMode(hdc, BACKGROUND_MODE.TRANSPARENT);
        _ = PInvoke.SetTextColor(hdc, color);
        RECT rect = new()
        {
            left = x,
            top = y,
            right = x + Math.Max(box.W, 1),
            bottom = y + Math.Max(box.H, 1),
        };
        DRAW_TEXT_FORMAT flags = DRAW_TEXT_FORMAT.DT_NOPREFIX;
        flags |= center ? DRAW_TEXT_FORMAT.DT_CENTER : DRAW_TEXT_FORMAT.DT_LEFT;
        flags |= wrap
            ? DRAW_TEXT_FORMAT.DT_WORDBREAK | DRAW_TEXT_FORMAT.DT_TOP
            : DRAW_TEXT_FORMAT.DT_SINGLELINE | DRAW_TEXT_FORMAT.DT_VCENTER | DRAW_TEXT_FORMAT.DT_END_ELLIPSIS;
        unsafe
        {
            fixed (char* chars = text)
            {
                _ = PInvoke.DrawText(hdc, chars, text.Length, ref rect, flags);
            }
        }

        _ = PInvoke.SelectObject(hdc, old);
    }
}
