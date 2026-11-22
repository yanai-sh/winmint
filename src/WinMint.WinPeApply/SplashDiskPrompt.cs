using System.Globalization;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace WinMint.WinPeApply;

/// <summary>
/// One screen: the target-disk prompt. Equal side margins, nothing selected until Enter.
/// Choosing a row does not erase the disk.
/// </summary>
internal static class SplashDiskPrompt
{
    internal const string Heading = "Target disk";
    internal const string Lead = "WinMint installs Windows on one whole disk. Nothing is selected until you press Enter.";
    internal const string Action = "Choose this disk";

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

    internal static string Marked(SplashDisk disk)
    {
        string name = string.IsNullOrWhiteSpace(disk.Model)
            ? string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}, {disk.Size}")
            : string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}, {disk.Size}, {disk.Model}");
        return name + " is marked. The disk was not erased.";
    }

    internal readonly record struct Box(int X, int Y, int W, int H)
    {
        internal int Right => X + W;

        internal int Bottom => Y + H;
    }

    internal readonly record struct PromptLayout(
        int Margin,
        Box Mark,
        Box HeadingBox,
        Box LeadBox,
        Box FactBox,
        Box List,
        int RowHeight,
        int RowGap,
        Box Button);

    internal static int Px(int px, int dpi) => Math.Max(1, px * Math.Max(dpi, 96) / 96);

    internal static PromptLayout Measure(int width, int height, int dpi, int rows)
    {
        width = Math.Max(width, 1);
        height = Math.Max(height, 1);
        rows = Math.Max(rows, 0);
        int gutter = width < Px(640, dpi) ? Px(24, dpi) : Px(80, dpi);
        int column = Math.Min(Px(720, dpi), Math.Max(Px(240, dpi), width - (2 * gutter)));
        int margin = Math.Max(0, (width - column) / 2);
        return Stack(height, dpi, rows, margin, column, showMark: true, leadLines: 3, rowGap: 8, top: 48);
    }

    private static PromptLayout Stack(
        int height,
        int dpi,
        int rows,
        int margin,
        int column,
        bool showMark,
        int leadLines,
        int rowGap,
        int top)
    {
        int y = Px(top, dpi);
        int markH = showMark ? Math.Min(Px(96, dpi), Math.Max(Px(48, dpi), column / 4)) : 0;
        int markW = showMark ? Math.Min(column, markH * 4) : 0;
        Box mark = new(margin, y, markW, markH);
        if (showMark)
        {
            y = mark.Bottom + Px(32, dpi);
        }

        Box heading = new(margin, y, column, Px(40, dpi));
        y = heading.Bottom + Px(16, dpi);
        Box lead = new(margin, y, column, Px(24 * leadLines, dpi));
        y = lead.Bottom + Px(16, dpi);
        Box fact = new(margin, y, column, Px(48, dpi));
        y = fact.Bottom + Px(24, dpi);
        int rowH = Px(48, dpi);
        int gap = rows > 1 ? Px(rowGap, dpi) : 0;
        int listH = rows == 0 ? 0 : (rows * rowH) + ((rows - 1) * gap);
        Box list = new(margin, y, column, listH);
        y = (rows == 0 ? fact.Bottom : list.Bottom) + Px(32, dpi);
        int buttonW = margin + column < Px(640, dpi) ? column : Math.Min(column, Px(196, dpi));
        Box button = new(margin, y, buttonW, Px(44, dpi));
        int limit = height - Px(24, dpi);
        if (button.Bottom > limit && showMark)
        {
            return Stack(height, dpi, rows, margin, column, showMark: false, leadLines, rowGap, top);
        }

        if (button.Bottom > limit && leadLines > 1)
        {
            return Stack(height, dpi, rows, margin, column, showMark, leadLines: 1, rowGap, top);
        }

        if (button.Bottom > limit && rowGap > 0)
        {
            return Stack(height, dpi, rows, margin, column, showMark, leadLines, rowGap: 0, top);
        }

        if (button.Bottom > limit && top > 24)
        {
            return Stack(height, dpi, rows, margin, column, showMark, leadLines, rowGap, top: 24);
        }

        return new PromptLayout(margin, mark, heading, lead, fact, list, rowH, gap, button);
    }
}

internal sealed class SplashPromptPainter : IDisposable
{
    private const int LiftPx = 2;
    private const int PressPx = 1;
    private const int RingPx = 2;
    private const int RadiusPx = 4;

    private static readonly COLORREF Ink = new(0x00FBF7F3);
    private static readonly COLORREF Muted = new(0x00C5B4A8);
    private static readonly COLORREF Hair = new(0x00262524);
    private static readonly COLORREF Ground = new(0x00000000);
    private static readonly COLORREF MintHover = new(0x009CD563);
    private static readonly COLORREF MintPress = new(0x0078B341);
    private static readonly COLORREF Mint = new(0x008CD04C);
    private static readonly COLORREF ButtonInk = new(0x00161814);
    private static readonly COLORREF FocusFill = new(0x001C1814);

    private HFONT _heading;
    private HFONT _body;
    private HFONT _button;
    private int _dpi = 96;
    private int _headingPx;
    private bool _ready;

    internal void Paint(HDC hdc, RECT client, int dpi, IReadOnlyList<SplashDisk> disks, int focus, int marked, bool pressed)
    {
        int width = client.right - client.left;
        int height = client.bottom - client.top;
        EnsureFonts(dpi, width);
        SplashDiskPrompt.PromptLayout layout = SplashDiskPrompt.Measure(width, height, _dpi, disks.Count);
        if (layout.Mark.H >= 16)
        {
            _ = BrandLockup.TryBlitAt(hdc, client.left + layout.Mark.X, client.top + layout.Mark.Y, layout.Mark.W, layout.Mark.H, out _);
        }

        Text(hdc, _heading, Ink, SplashDiskPrompt.Heading, client, layout.HeadingBox, wrap: false);
        Text(hdc, _body, Ink, SplashDiskPrompt.Lead, client, layout.LeadBox, wrap: true);
        string fact = marked >= 0 && marked < disks.Count
            ? SplashDiskPrompt.Marked(disks[marked])
            : SplashDiskPrompt.Fact(disks.Count);
        Text(hdc, _body, Ink, fact, client, layout.FactBox, wrap: true);

        for (int i = 0; i < disks.Count; i++)
        {
            if (i == focus)
            {
                continue;
            }

            DrawRow(hdc, client, layout, disks[i], i, focused: false);
        }

        if (focus >= 0 && focus < disks.Count)
        {
            DrawRow(hdc, client, layout, disks[focus], focus, focused: true);
        }

        if (disks.Count > 0)
        {
            DrawButton(hdc, client, layout, focus >= 0, pressed);
        }
    }

    public void Dispose() => FreeFonts();

    private void DrawRow(HDC hdc, RECT client, SplashDiskPrompt.PromptLayout layout, SplashDisk disk, int index, bool focused)
    {
        int lift = focused ? SplashDiskPrompt.Px(LiftPx, _dpi) : 0;
        int y = client.top + layout.List.Y + (index * (layout.RowHeight + layout.RowGap)) - lift;
        int x = client.left + layout.List.X;
        int radius = SplashDiskPrompt.Px(RadiusPx, _dpi);
        if (focused)
        {
            int ring = SplashDiskPrompt.Px(RingPx, _dpi);
            Round(hdc, x, y, layout.List.W, layout.RowHeight, Mint, radius: radius);
            Round(hdc, x + ring, y + ring, layout.List.W - (2 * ring), layout.RowHeight - (2 * ring), FocusFill, radius: radius);
        }
        else
        {
            Hairline(hdc, x, y + layout.RowHeight - 1, x + layout.List.W);
        }

        int pad = SplashDiskPrompt.Px(16, _dpi);
        int numberW = SplashDiskPrompt.Px(96, _dpi);
        int sizeW = SplashDiskPrompt.Px(120, _dpi);
        int textY = y;
        int textH = layout.RowHeight;
        Text(hdc, _body, Ink, string.Create(CultureInfo.InvariantCulture, $"Disk {disk.Number}"), default, new SplashDiskPrompt.Box(x + pad, textY, numberW, textH), wrap: false, absolute: true);
        Text(hdc, _body, Ink, disk.Size, default, new SplashDiskPrompt.Box(x + pad + numberW, textY, sizeW, textH), wrap: false, absolute: true);
        if (!string.IsNullOrWhiteSpace(disk.Model))
        {
            int modelX = x + pad + numberW + sizeW;
            Text(hdc, _body, Muted, disk.Model, default, new SplashDiskPrompt.Box(modelX, textY, x + layout.List.W - pad - modelX, textH), wrap: false, absolute: true);
        }
    }

    private void DrawButton(HDC hdc, RECT client, SplashDiskPrompt.PromptLayout layout, bool armed, bool pressed)
    {
        int y = client.top + layout.Button.Y + (armed && pressed ? SplashDiskPrompt.Px(PressPx, _dpi) : 0);
        int x = client.left + layout.Button.X;
        COLORREF fill = armed ? (pressed ? MintPress : MintHover) : Ground;
        COLORREF edge = armed ? fill : Muted;
        Round(hdc, x, y, layout.Button.W, layout.Button.H, fill, edge, SplashDiskPrompt.Px(RadiusPx, _dpi));
        Text(
            hdc,
            _button,
            armed ? ButtonInk : Ink,
            SplashDiskPrompt.Action,
            default,
            new SplashDiskPrompt.Box(x, y, layout.Button.W, layout.Button.H),
            wrap: false,
            absolute: true,
            center: true);
    }

    private void EnsureFonts(int dpi, int width)
    {
        int headingPx = width < SplashDiskPrompt.Px(640, dpi) ? 28 : 32;
        if (_ready && _dpi == dpi && _headingPx == headingPx)
        {
            return;
        }

        FreeFonts();
        _dpi = Math.Max(dpi, 96);
        _headingPx = headingPx;
        _heading = Font(SplashDiskPrompt.Px(headingPx, _dpi), 600);
        _body = Font(SplashDiskPrompt.Px(16, _dpi), 400);
        _button = Font(SplashDiskPrompt.Px(16, _dpi), 500);
        _ready = !_heading.IsNull && !_body.IsNull && !_button.IsNull;
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
        Drop(ref _heading);
        Drop(ref _body);
        Drop(ref _button);
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
        DRAW_TEXT_FORMAT flags = DRAW_TEXT_FORMAT.DT_NOPREFIX | DRAW_TEXT_FORMAT.DT_NOCLIP;
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

    private static void Round(HDC hdc, int x, int y, int w, int h, COLORREF fill, COLORREF? edge = null, int radius = RadiusPx)
    {
        int corner = Math.Max(2, radius * 2);
        HBRUSH brush = PInvoke.CreateSolidBrush(fill);
        HPEN pen = PInvoke.CreatePen(PEN_STYLE.PS_SOLID, 1, edge ?? fill);
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
}
