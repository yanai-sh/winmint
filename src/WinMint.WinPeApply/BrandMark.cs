using System.Drawing;
using System.Text;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;

namespace WinMint.WinPeApply;

/// <summary>
/// Solid-fill icon parsed from the embedded lockup <c>assets/brand/readme/dark.svg</c>.
/// The splash paints that file through <see cref="BrandLockup"/>; this draws the icon when Direct2D cannot.
/// </summary>
internal static class BrandMark
{
    internal const int MarkSize = 120;
    internal const string ResourceName = "WinMint.WinPeApply.BrandMark.svg";

    // Solid fills in the lockup are the icon plus the two wordmark i-dots.
    // The icon starts span about 370 user units; the next solid fill is the WIN i-dot, much further right.
    private const float IconClusterReach = 500f;

    private static readonly MarkShape[] Cached = Parse(ReadEmbedded());

    internal static MarkShape[] Shapes => Cached;

    internal static void Draw(HDC hdc, int cx, int cy) => Draw(hdc, cx, cy, MarkSize);

    internal static MarkPlacement Placement(int size)
    {
        if (!TryBounds(Shapes, out float minX, out float minY, out float maxX, out float maxY))
        {
            throw new InvalidOperationException("Brand mark has no extent.");
        }

        float span = MathF.Max(maxX - minX, maxY - minY);
        if (span <= 0)
        {
            throw new InvalidOperationException("Brand mark has no extent.");
        }

        return new MarkPlacement(size / span, (minX + maxX) * 0.5f, (minY + maxY) * 0.5f);
    }

    internal static byte[] EmbeddedSvg()
    {
        using Stream stream = OpenEmbedded();
        using MemoryStream copy = new();
        stream.CopyTo(copy);
        return copy.ToArray();
    }

    internal static MarkShape[] Parse(string svg)
    {
        List<SolidPath> solids = [];
        int i = 0;
        while (true)
        {
            int at = svg.IndexOf("<path", i, StringComparison.Ordinal);
            if (at < 0)
            {
                break;
            }

            int end = svg.IndexOf('>', at);
            if (end < 0)
            {
                break;
            }

            ReadOnlySpan<char> tag = svg.AsSpan(at, end - at);
            i = end + 1;
            if (!TryAttr(tag, "fill", out ReadOnlySpan<char> fill) || !TryAttr(tag, "d", out ReadOnlySpan<char> data))
            {
                continue;
            }

            if (!TryParseColor(fill, out uint rgb) || !TryStartPoint(data, out float startX, out _))
            {
                continue;
            }

            solids.Add(new SolidPath(rgb, new string(data), startX));
        }

        if (solids.Count == 0)
        {
            throw new InvalidOperationException("Brand lockup has no solid-fill paths.");
        }

        float origin = float.PositiveInfinity;
        foreach (SolidPath solid in solids)
        {
            if (solid.StartX < origin)
            {
                origin = solid.StartX;
            }
        }

        List<MarkShape> mark = [];
        foreach (SolidPath solid in solids)
        {
            if (solid.StartX > (origin + IconClusterReach))
            {
                continue;
            }

            if (!TryParsePath(solid.Data, out MarkFigure[] figures, out string error))
            {
                throw new InvalidOperationException("Brand mark path could not be parsed: " + error);
            }

            mark.Add(new MarkShape(solid.Rgb, figures));
        }

        if (mark.Count == 0)
        {
            throw new InvalidOperationException("Brand lockup mark cluster is empty.");
        }

        return [.. mark];
    }

    /// <summary>Off-screen paint of the boot-splash mark. Pixels are COLORREF values, row-major.</summary>
    internal static uint[] Rasterize(int canvas, int markSize)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(canvas);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(markSize);

        HDC screen = PInvoke.GetDC(HWND.Null);
        if (screen.IsNull)
        {
            throw new InvalidOperationException("GetDC failed.");
        }

        HDC mem = default;
        HBITMAP bmp = default;
        HGDIOBJ previous = default;
        try
        {
            mem = PInvoke.CreateCompatibleDC(screen);
            if (mem.IsNull)
            {
                throw new InvalidOperationException("CreateCompatibleDC failed.");
            }

            bmp = PInvoke.CreateCompatibleBitmap(screen, canvas, canvas);
            if (bmp.IsNull)
            {
                throw new InvalidOperationException("CreateCompatibleBitmap failed.");
            }

            previous = PInvoke.SelectObject(mem, bmp);
            Fill(mem, canvas, new COLORREF(0));
            Draw(mem, canvas / 2, canvas / 2, markSize);

            uint[] pixels = new uint[canvas * canvas];
            for (int y = 0; y < canvas; y++)
            {
                for (int x = 0; x < canvas; x++)
                {
                    COLORREF pixel = PInvoke.GetPixel(mem, x, y);
                    uint value = pixel.Value;
                    if (value == 0xFFFFFFFFu)
                    {
                        throw new InvalidOperationException($"GetPixel failed at {x},{y}.");
                    }

                    pixels[(y * canvas) + x] = value;
                }
            }

            return pixels;
        }
        finally
        {
            if (!previous.IsNull && !mem.IsNull)
            {
                _ = PInvoke.SelectObject(mem, previous);
            }

            if (!bmp.IsNull)
            {
                _ = PInvoke.DeleteObject(bmp);
            }

            if (!mem.IsNull)
            {
                _ = PInvoke.DeleteDC(mem);
            }

            _ = PInvoke.ReleaseDC(HWND.Null, screen);
        }
    }

    internal static uint ToColorRef(uint rgb)
    {
        uint r = (rgb >> 16) & 0xFFu;
        uint g = (rgb >> 8) & 0xFFu;
        uint b = rgb & 0xFFu;
        return (b << 16) | (g << 8) | r;
    }

    private static void Draw(HDC hdc, int cx, int cy, int size)
    {
        MarkPlacement place = Placement(size);
        foreach (MarkShape shape in Shapes)
        {
            Paint(hdc, shape, place, cx, cy);
        }
    }

    private static void Paint(HDC hdc, MarkShape shape, MarkPlacement place, int cx, int cy)
    {
        if (!PInvoke.BeginPath(hdc))
        {
            return;
        }

        Span<Point> curve = stackalloc Point[3];
        foreach (MarkFigure figure in shape.Figures)
        {
            _ = PInvoke.MoveToEx(hdc, place.MapX(figure.StartX, cx), place.MapY(figure.StartY, cy));
            foreach (MarkSeg seg in figure.Segs)
            {
                if (seg.IsLine)
                {
                    _ = PInvoke.LineTo(hdc, place.MapX(seg.X, cx), place.MapY(seg.Y, cy));
                    continue;
                }

                curve[0] = new Point(place.MapX(seg.X1, cx), place.MapY(seg.Y1, cy));
                curve[1] = new Point(place.MapX(seg.X2, cx), place.MapY(seg.Y2, cy));
                curve[2] = new Point(place.MapX(seg.X, cx), place.MapY(seg.Y, cy));
                _ = PInvoke.PolyBezierTo(hdc, curve);
            }

            _ = PInvoke.CloseFigure(hdc);
        }

        if (!PInvoke.EndPath(hdc))
        {
            _ = PInvoke.AbortPath(hdc);
            return;
        }

        HBRUSH brush = PInvoke.CreateSolidBrush(new COLORREF(ToColorRef(shape.Rgb)));
        HGDIOBJ old = PInvoke.SelectObject(hdc, brush);
        _ = PInvoke.SetPolyFillMode(hdc, CREATE_POLYGON_RGN_MODE.WINDING);
        _ = PInvoke.FillPath(hdc);
        _ = PInvoke.SelectObject(hdc, old);
        _ = PInvoke.DeleteObject(brush);
    }

    private static void Fill(HDC hdc, int size, COLORREF color)
    {
        HBRUSH brush = PInvoke.CreateSolidBrush(color);
        HGDIOBJ old = PInvoke.SelectObject(hdc, brush);
        _ = PInvoke.PatBlt(hdc, 0, 0, size, size, ROP_CODE.PATCOPY);
        _ = PInvoke.SelectObject(hdc, old);
        _ = PInvoke.DeleteObject(brush);
    }

    private static bool TryBounds(MarkShape[] shapes, out float minX, out float minY, out float maxX, out float maxY)
    {
        minX = float.PositiveInfinity;
        minY = float.PositiveInfinity;
        maxX = float.NegativeInfinity;
        maxY = float.NegativeInfinity;
        bool any = false;
        foreach (MarkShape shape in shapes)
        {
            foreach (MarkFigure figure in shape.Figures)
            {
                Include(ref minX, ref minY, ref maxX, ref maxY, figure.StartX, figure.StartY);
                any = true;
                foreach (MarkSeg seg in figure.Segs)
                {
                    if (!seg.IsLine)
                    {
                        Include(ref minX, ref minY, ref maxX, ref maxY, seg.X1, seg.Y1);
                        Include(ref minX, ref minY, ref maxX, ref maxY, seg.X2, seg.Y2);
                    }

                    Include(ref minX, ref minY, ref maxX, ref maxY, seg.X, seg.Y);
                }
            }
        }

        return any;
    }

    private static void Include(ref float minX, ref float minY, ref float maxX, ref float maxY, float x, float y)
    {
        minX = MathF.Min(minX, x);
        minY = MathF.Min(minY, y);
        maxX = MathF.Max(maxX, x);
        maxY = MathF.Max(maxY, y);
    }

    private static string ReadEmbedded()
    {
        using Stream stream = OpenEmbedded();
        using StreamReader reader = new(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    private static Stream OpenEmbedded()
    {
        Stream? stream = typeof(BrandMark).Assembly.GetManifestResourceStream(ResourceName);
        if (stream is null)
        {
            throw new InvalidOperationException("Missing embedded brand mark " + ResourceName + ".");
        }

        return stream;
    }

    private static bool TryAttr(ReadOnlySpan<char> tag, string name, out ReadOnlySpan<char> value)
    {
        string key = name + "=\"";
        int at = tag.IndexOf(key, StringComparison.Ordinal);
        if (at < 0)
        {
            value = default;
            return false;
        }

        at += key.Length;
        int end = tag[at..].IndexOf('"');
        if (end < 0)
        {
            value = default;
            return false;
        }

        value = tag.Slice(at, end);
        return true;
    }

    private static bool TryParseColor(ReadOnlySpan<char> fill, out uint rgb)
    {
        rgb = 0;
        if (fill.Length != 7 || fill[0] != '#')
        {
            return false;
        }

        uint value = 0;
        for (int i = 1; i < 7; i++)
        {
            int digit = Hex(fill[i]);
            if (digit < 0)
            {
                return false;
            }

            value = (value << 4) | (uint)digit;
        }

        rgb = value;
        return true;
    }

    private static int Hex(char c) => c switch
    {
        >= '0' and <= '9' => c - '0',
        >= 'a' and <= 'f' => c - 'a' + 10,
        >= 'A' and <= 'F' => c - 'A' + 10,
        _ => -1,
    };

    private static bool TryStartPoint(ReadOnlySpan<char> data, out float x, out float y)
    {
        x = 0;
        y = 0;
        int i = 0;
        Skip(data, ref i);
        if (i >= data.Length || data[i] is not ('M' or 'm'))
        {
            return false;
        }

        i++;
        return TryRead(data, ref i, out x) && TryRead(data, ref i, out y);
    }

    private static bool TryParsePath(string data, out MarkFigure[] figures, out string error)
    {
        figures = [];
        error = string.Empty;
        ReadOnlySpan<char> d = data.AsSpan();
        PathBuilder builder = new();
        int i = 0;
        char cmd = '\0';
        char repeat = '\0';
        bool any = false;
        while (true)
        {
            Skip(d, ref i);
            if (i >= d.Length)
            {
                break;
            }

            char c = d[i];
            if (IsCommand(c))
            {
                cmd = c;
                i++;
                repeat = cmd switch
                {
                    'M' => 'L',
                    'm' => 'l',
                    'Z' or 'z' => '\0',
                    _ => cmd,
                };
            }
            else if (repeat == '\0')
            {
                error = "expected a path command";
                return false;
            }
            else
            {
                cmd = repeat;
            }

            any = true;
            switch (cmd)
            {
                case 'M':
                    if (!TryReadPair(d, ref i, out float mx, out float my))
                    {
                        error = "moveto needs two numbers";
                        return false;
                    }

                    builder.MoveTo(mx, my);
                    repeat = 'L';
                    break;
                case 'm':
                    if (!TryReadPair(d, ref i, out float dx, out float dy))
                    {
                        error = "moveto needs two numbers";
                        return false;
                    }

                    builder.MoveTo(builder.HasPoint ? builder.X + dx : dx, builder.HasPoint ? builder.Y + dy : dy);
                    repeat = 'l';
                    break;
                case 'L':
                    if (!TryReadPair(d, ref i, out float lx, out float ly) || !builder.LineTo(lx, ly))
                    {
                        error = "lineto needs a current point and two numbers";
                        return false;
                    }

                    break;
                case 'l':
                    if (!TryReadPair(d, ref i, out float ldx, out float ldy) || !builder.LineTo(builder.X + ldx, builder.Y + ldy))
                    {
                        error = "lineto needs a current point and two numbers";
                        return false;
                    }

                    break;
                case 'H':
                    if (!TryRead(d, ref i, out float hx) || !builder.LineTo(hx, builder.Y))
                    {
                        error = "horizontal lineto needs a current point and a number";
                        return false;
                    }

                    break;
                case 'h':
                    if (!TryRead(d, ref i, out float hdx) || !builder.LineTo(builder.X + hdx, builder.Y))
                    {
                        error = "horizontal lineto needs a current point and a number";
                        return false;
                    }

                    break;
                case 'V':
                    if (!TryRead(d, ref i, out float vy) || !builder.LineTo(builder.X, vy))
                    {
                        error = "vertical lineto needs a current point and a number";
                        return false;
                    }

                    break;
                case 'v':
                    if (!TryRead(d, ref i, out float vdy) || !builder.LineTo(builder.X, builder.Y + vdy))
                    {
                        error = "vertical lineto needs a current point and a number";
                        return false;
                    }

                    break;
                case 'C':
                    if (!TryReadCubic(d, ref i, out float x1, out float y1, out float x2, out float y2, out float x, out float y)
                        || !builder.CubicTo(x1, y1, x2, y2, x, y))
                    {
                        error = "curveto needs a current point and six numbers";
                        return false;
                    }

                    break;
                case 'c':
                    if (!TryReadCubic(d, ref i, out float dx1, out float dy1, out float dx2, out float dy2, out float cdx, out float cdy)
                        || !builder.HasPoint
                        || !builder.CubicTo(builder.X + dx1, builder.Y + dy1, builder.X + dx2, builder.Y + dy2, builder.X + cdx, builder.Y + cdy))
                    {
                        error = "curveto needs a current point and six numbers";
                        return false;
                    }

                    break;
                case 'Z':
                case 'z':
                    if (!builder.Close())
                    {
                        error = "closepath before moveto";
                        return false;
                    }

                    repeat = '\0';
                    break;
                default:
                    error = "unsupported path command '" + cmd + "'";
                    return false;
            }
        }

        if (!any)
        {
            error = "empty path";
            return false;
        }

        figures = builder.Finish();
        if (figures.Length == 0)
        {
            error = "path has no figure";
            return false;
        }

        return true;
    }

    private static bool IsCommand(char c) => c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z');

    private static void Skip(ReadOnlySpan<char> data, ref int i)
    {
        while (i < data.Length && data[i] is ' ' or '\t' or '\r' or '\n' or ',')
        {
            i++;
        }
    }

    private static bool TryReadPair(ReadOnlySpan<char> data, ref int i, out float x, out float y)
    {
        y = 0;
        return TryRead(data, ref i, out x) && TryRead(data, ref i, out y);
    }

    private static bool TryReadCubic(
        ReadOnlySpan<char> data,
        ref int i,
        out float x1,
        out float y1,
        out float x2,
        out float y2,
        out float x,
        out float y)
    {
        y1 = 0;
        x2 = 0;
        y2 = 0;
        x = 0;
        y = 0;
        return TryRead(data, ref i, out x1)
            && TryRead(data, ref i, out y1)
            && TryRead(data, ref i, out x2)
            && TryRead(data, ref i, out y2)
            && TryRead(data, ref i, out x)
            && TryRead(data, ref i, out y);
    }

    private static bool TryRead(ReadOnlySpan<char> data, ref int i, out float value)
    {
        value = 0;
        Skip(data, ref i);
        if (i >= data.Length || IsCommand(data[i]))
        {
            return false;
        }

        int start = i;
        int sign = 1;
        if (data[i] == '+')
        {
            i++;
        }
        else if (data[i] == '-')
        {
            sign = -1;
            i++;
        }

        long ip = 0;
        bool any = false;
        while (i < data.Length && data[i] is >= '0' and <= '9')
        {
            any = true;
            ip = (ip * 10) + (data[i] - '0');
            i++;
        }

        long fp = 0;
        int fd = 0;
        if (i < data.Length && data[i] == '.')
        {
            i++;
            while (i < data.Length && data[i] is >= '0' and <= '9')
            {
                any = true;
                fp = (fp * 10) + (data[i] - '0');
                fd++;
                i++;
            }
        }

        if (!any)
        {
            i = start;
            return false;
        }

        float number = ip;
        if (fd > 0)
        {
            number += fp / MathF.Pow(10, fd);
        }

        value = sign * number;
        return true;
    }

    private readonly record struct SolidPath(uint Rgb, string Data, float StartX);

    private sealed class PathBuilder
    {
        private readonly List<MarkFigure> _figures = [];
        private readonly List<MarkSeg> _segs = [];
        private float _sx;
        private float _sy;
        private bool _open;

        internal float X { get; private set; }

        internal float Y { get; private set; }

        internal bool HasPoint { get; private set; }

        internal void MoveTo(float x, float y)
        {
            Flush();
            _sx = X = x;
            _sy = Y = y;
            _open = true;
            HasPoint = true;
        }

        internal bool LineTo(float x, float y)
        {
            if (!HasPoint)
            {
                return false;
            }

            if (!_open)
            {
                MoveTo(X, Y);
            }

            _segs.Add(MarkSeg.LineTo(x, y));
            X = x;
            Y = y;
            return true;
        }

        internal bool CubicTo(float x1, float y1, float x2, float y2, float x, float y)
        {
            if (!HasPoint)
            {
                return false;
            }

            if (!_open)
            {
                MoveTo(X, Y);
            }

            _segs.Add(MarkSeg.Curve(x1, y1, x2, y2, x, y));
            X = x;
            Y = y;
            return true;
        }

        internal bool Close()
        {
            if (!_open && !HasPoint)
            {
                return false;
            }

            Flush();
            X = _sx;
            Y = _sy;
            return true;
        }

        internal MarkFigure[] Finish()
        {
            Flush();
            return [.. _figures];
        }

        private void Flush()
        {
            if (!_open)
            {
                return;
            }

            if (_segs.Count > 0)
            {
                _figures.Add(new MarkFigure(_sx, _sy, [.. _segs]));
            }

            _segs.Clear();
            _open = false;
        }
    }
}

internal sealed class MarkShape(uint rgb, MarkFigure[] figures)
{
    internal uint Rgb { get; } = rgb;

    internal MarkFigure[] Figures { get; } = figures;
}

internal sealed class MarkFigure(float startX, float startY, MarkSeg[] segs)
{
    internal float StartX { get; } = startX;

    internal float StartY { get; } = startY;

    internal MarkSeg[] Segs { get; } = segs;
}

internal readonly record struct MarkSeg(bool IsLine, float X1, float Y1, float X2, float Y2, float X, float Y)
{
    internal static MarkSeg LineTo(float x, float y) => new(true, 0, 0, 0, 0, x, y);

    internal static MarkSeg Curve(float x1, float y1, float x2, float y2, float x, float y) =>
        new(false, x1, y1, x2, y2, x, y);
}

internal readonly record struct MarkPlacement(float Scale, float MidX, float MidY)
{
    internal int MapX(float x, int cx) => (int)MathF.Round(cx + ((x - MidX) * Scale));

    internal int MapY(float y, int cy) => (int)MathF.Round(cy + ((y - MidY) * Scale));
}
