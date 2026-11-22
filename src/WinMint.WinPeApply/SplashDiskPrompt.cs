using System.Globalization;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace WinMint.WinPeApply;

/// <summary>
/// Disk list drawn under the large lockup. Equal side margins, nothing selected until Enter.
/// Choosing a row does not erase the disk. The lockup's own frame stays the apply splash.
/// </summary>
internal static class SplashDiskPrompt
{
    internal const string Heading = "Target disk";
    internal const string Lead = "WinMint installs Windows on one whole disk. Nothing is selected until you press Enter.";
    internal const string Action = "Choose this disk";
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

    internal static PromptLayout Measure(int width, int height, int dpi, int rows, int minY = 0, string? fact = null)
    {
        width = Math.Max(width, 1);
        height = Math.Max(height, 1);
        rows = Math.Max(rows, 0);
        int gutter = width < Px(640, dpi) ? Px(24, dpi) : Px(80, dpi);
        int column = Math.Min(Px(720, dpi), Math.Max(Px(240, dpi), width - (2 * gutter)));
        int margin = Math.Max(0, (width - column) / 2);
        int origin = Math.Max(0, minY);
        int limit = height - Px(24, dpi);
        string factText = string.IsNullOrEmpty(fact) ? Fact(rows) : fact;
        int leadLines = Lines(Lead, column, dpi);
        int factLines = Lines(factText, column, dpi);
        PromptLayout layout = default;
        foreach (Rhythm rhythm in Rhythms)
        {
            layout = Place(dpi, rows, margin, column, origin, leadLines, factLines, rhythm);
            if (Fits(layout, rows, limit))
            {
                return layout;
            }
        }

        layout = Place(dpi, rows, margin, column, origin, leadLines: 1, factLines: 1, Rhythms[^1]);
        return layout;
    }

    private static int Lines(string text, int column, int dpi)
    {
        int perLine = Math.Max(8, column / Px(9, dpi));
        return Math.Clamp((text.Length + perLine - 1) / perLine, 1, 6);
    }

    private static bool Fits(PromptLayout layout, int rows, int limit)
    {
        int bottom = rows == 0 ? layout.FactBox.Bottom : layout.Button.Bottom;
        return bottom <= limit;
    }

    private static PromptLayout Place(
        int dpi,
        int rows,
        int margin,
        int column,
        int origin,
        int leadLines,
        int factLines,
        Rhythm rhythm)
    {
        int y = origin;
        Box heading = new(margin, y, column, Px(rhythm.Heading, dpi));
        y = heading.Bottom + Px(rhythm.GapHead, dpi);
        Box lead = new(margin, y, column, Px(24, dpi) * Math.Max(leadLines, 1));
        y = lead.Bottom + Px(rhythm.GapLead, dpi);
        Box fact = new(margin, y, column, Px(24, dpi) * Math.Max(factLines, 1));
        y = fact.Bottom + Px(rhythm.GapFact, dpi);
        int rowH = Px(rhythm.Row, dpi);
        int gap = rows > 1 && rhythm.RowGap > 0 ? Px(rhythm.RowGap, dpi) : 0;
        int listH = rows == 0 ? 0 : (rows * rowH) + ((rows - 1) * gap);
        Box list = new(margin, y, column, listH);
        y = (rows == 0 ? fact.Bottom : list.Bottom) + Px(rhythm.GapButton, dpi);
        int buttonW = margin + column < Px(640, dpi) ? column : Math.Min(column, Px(196, dpi));
        Box button = new(margin, y, buttonW, Px(44, dpi));
        return new PromptLayout(margin, default, heading, lead, fact, list, rowH, gap, button);
    }

    // Roomy first. Later rows only give up gap and row height, never the lockup above them.
    private static readonly Rhythm[] Rhythms =
    [
        new(40, 12, 12, 16, 48, 8, 24),
        new(40, 8, 8, 8, 48, 0, 16),
        new(32, 4, 4, 4, 44, 0, 8),
    ];

    private readonly record struct Rhythm(int Heading, int GapHead, int GapLead, int GapFact, int Row, int RowGap, int GapButton);
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
        int minY = HeroBand(hdc, client, dpi);
        string fact = marked >= 0 && marked < disks.Count
            ? SplashDiskPrompt.Marked(disks[marked])
            : SplashDiskPrompt.Fact(disks.Count);
        SplashDiskPrompt.PromptLayout layout = SplashDiskPrompt.Measure(width, height, dpi, disks.Count, minY, fact);
        EnsureFonts(dpi, layout.HeadingBox.H);

        Text(hdc, _heading, Ink, SplashDiskPrompt.Heading, client, layout.HeadingBox, wrap: false);
        Text(hdc, _body, Ink, SplashDiskPrompt.Lead, client, layout.LeadBox, wrap: true);
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
        int shift = armed
            ? (pressed ? SplashDiskPrompt.Px(PressPx, _dpi) : -SplashDiskPrompt.Px(1, _dpi))
            : 0;
        int y = client.top + layout.Button.Y + shift;
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

    private void EnsureFonts(int dpi, int headingBox)
    {
        int headingPx = headingBox >= SplashDiskPrompt.Px(40, dpi) ? 32 : 28;
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
