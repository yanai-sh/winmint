using System.Globalization;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace WinMint.WinPeApply;

/// <summary>
/// Centered disk lines under the large lockup. The first disk starts focused.
/// A mint asterisk marks that row. Arrow keys and a click move it. Enter marks that disk.
/// </summary>
internal static class SplashDiskPrompt
{
    internal const string Heading = "Target disk";
    internal const string Lead = "Nothing is selected. Press the arrow keys, or click a disk.";
    internal const string Asterisk = "*";
    internal const int AsteriskWidth = 28;
    internal const int HeroGap = 16;

    internal static int PromptTop(int heroBottom, int dpi) => heroBottom + Px(HeroGap, dpi);

    internal static int InitialFocus(int count) => count > 0 ? 0 : -1;

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

    private static string Name(SplashDisk disk) => string.Create(CultureInfo.InvariantCulture, $"(Disk {disk.Number})");

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

    internal static PromptLayout Measure(int width, int dpi, int rows, int minY = 0)
    {
        width = Math.Max(width, 1);
        rows = Math.Max(rows, 0);
        int gutter = width < Px(640, dpi) ? Px(24, dpi) : Px(80, dpi);
        int column = Math.Min(Px(560, dpi), Math.Max(Px(240, dpi), width - (2 * gutter)));
        int margin = Math.Max(0, (width - column) / 2);
        int origin = Math.Max(0, minY);
        int rowH = Px(40, dpi);
        int rowGap = rows > 1 ? Px(8, dpi) : 0;
        Box statusBox = new(margin, origin, column, Px(24, dpi));
        int listY = statusBox.Bottom + Px(12, dpi);
        int listH = rows == 0 ? 0 : (rows * rowH) + ((rows - 1) * rowGap);
        Box list = new(margin, listY, column, listH);
        return new PromptLayout(margin, default, statusBox, list, rowH, rowGap);
    }

    internal static int RowAt(PromptLayout layout, int rows, int x, int y)
    {
        if (rows <= 0 || layout.List.H <= 0 || x < layout.List.X || x >= layout.List.Right || y < layout.List.Y)
        {
            return -1;
        }

        int stride = layout.RowHeight + layout.RowGap;
        int offset = y - layout.List.Y;
        if (stride <= 0 || offset < 0 || offset >= layout.List.H)
        {
            return -1;
        }

        int index = offset / stride;
        int within = offset - (index * stride);
        if (within >= layout.RowHeight || index >= rows)
        {
            return -1;
        }

        return index;
    }
}

internal sealed class SplashPromptPainter : IDisposable
{
    private static readonly COLORREF Ink = new(0x00FBF7F3);
    private static readonly COLORREF Mint = new(0x008CD04C);

    private HFONT _body;
    private int _dpi = 96;
    private bool _ready;
    private SplashDiskPrompt.PromptLayout _layout;
    private int _rows;
    private bool _hasLayout;

    internal void Paint(HDC hdc, RECT client, int dpi, IReadOnlyList<SplashDisk> disks, int focus, int marked)
    {
        int width = client.right - client.left;
        int minY = HeroBand(hdc, client, dpi);
        string status = Status(disks, focus, marked);
        SplashDiskPrompt.PromptLayout layout = SplashDiskPrompt.Measure(width, dpi, disks.Count, minY);
        _layout = layout;
        _rows = disks.Count;
        _hasLayout = true;
        EnsureFonts(dpi);
        Text(hdc, _body, Ink, status, client, layout.Status, wrap: false, center: true);

        for (int i = 0; i < disks.Count; i++)
        {
            DrawRow(hdc, client, layout, disks[i], i, focused: i == focus);
        }
    }

    public void Dispose() => FreeFonts();

    internal int RowAt(int x, int y) => _hasLayout ? SplashDiskPrompt.RowAt(_layout, _rows, x, y) : -1;

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
        int markW = SplashDiskPrompt.Px(SplashDiskPrompt.AsteriskWidth, _dpi);
        if (focused)
        {
            Text(
                hdc,
                _body,
                Mint,
                SplashDiskPrompt.Asterisk,
                default,
                new SplashDiskPrompt.Box(x, y, markW, layout.RowHeight),
                wrap: false,
                absolute: true,
                center: true);
        }

        Text(
            hdc,
            _body,
            Ink,
            SplashDiskPrompt.RowLabel(disk),
            default,
            new SplashDiskPrompt.Box(x + markW, y, Math.Max(1, layout.List.W - markW), layout.RowHeight),
            wrap: false,
            absolute: true,
            center: true);
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
