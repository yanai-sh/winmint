using WinMint.WinPeApply;

namespace WinMint.Tests;

public class BrandMarkTests
{
    [Fact]
    public void Embedded_svg_is_the_readme_dark_lockup()
    {
        string path = Path.Combine(TestRepo.Root, "assets", "brand", "readme", "dark.svg");
        byte[] file = File.ReadAllBytes(path);
        Assert.Equal(file, BrandMark.EmbeddedSvg());
    }

    [Fact]
    public void Mark_uses_the_three_icon_paths()
    {
        MarkShape[] shapes = BrandMark.Shapes;
        Assert.Equal(3, shapes.Length);
        Assert.Equal(0x1170F2u, shapes[0].Rgb);
        Assert.Equal(0x003984u, shapes[1].Rgb);
        Assert.Equal(0x4CD08Cu, shapes[2].Rgb);

        // assets/brand/readme/dark.svg solid fills M547.892 209.365, M770.436 461.371, M920.394 209.797.
        AssertNear(547.892f, 209.365f, shapes[0]);
        AssertNear(770.436f, 461.371f, shapes[1]);
        AssertNear(920.394f, 209.797f, shapes[2]);
        Assert.Equal(8, Cubics(shapes[0]));
        Assert.Equal(2, Lines(shapes[0]));
        Assert.Equal(7, Cubics(shapes[1]));
        Assert.Equal(2, Lines(shapes[1]));
        Assert.Equal(8, Cubics(shapes[2]));
        Assert.Equal(0, Lines(shapes[2]));

        // First relative cubic of the blue path ends at the start plus (115.559, 0.096).
        MarkSeg first = shapes[0].Figures[0].Segs[0];
        Assert.False(first.IsLine);
        Assert.InRange(first.X, 663.44f, 663.47f);
        Assert.InRange(first.Y, 209.45f, 209.48f);
    }

    [Fact]
    public void Raster_paints_each_icon_path()
    {
        const int canvas = 180;
        uint[] pixels = BrandMark.Rasterize(canvas, BrandMark.MarkSize);
        MarkShape[] shapes = BrandMark.Shapes;
        MarkPlacement place = BrandMark.Placement(BrandMark.MarkSize);
        int cx = canvas / 2;
        int cy = canvas / 2;
        for (int i = 0; i < shapes.Length; i++)
        {
            (float x, float y) = UniqueInterior(shapes, i);
            int px = place.MapX(x, cx);
            int py = place.MapY(y, cy);
            uint expected = BrandMark.ToColorRef(shapes[i].Rgb);
            Assert.Equal(expected, pixels[(py * canvas) + px]);
        }
    }

    [Fact]
    public void Raster_is_not_the_round_stand_in()
    {
        const int canvas = 180;
        uint[] pixels = BrandMark.Rasterize(canvas, BrandMark.MarkSize);
        uint green = BrandMark.ToColorRef(0x4CD08C);
        Assert.Equal(120, BrandMark.MarkSize);
        int cx = canvas / 2;
        int cy = canvas / 2;
        int x0 = cx - (BrandMark.MarkSize / 2);
        int y0 = cy - (BrandMark.MarkSize / 2);
        // Previous splash ellipse, inscribed in (x0+40, y0+4)-(x0+114, y0+62).
        float ecx = x0 + 77f;
        float ecy = y0 + 33f;
        const float rx = 37f;
        const float ry = 29f;
        int holes = 0;
        int outside = 0;
        int area = 0;
        for (int y = 0; y < canvas; y++)
        {
            for (int x = 0; x < canvas; x++)
            {
                float nx = (x + 0.5f - ecx) / rx;
                float ny = (y + 0.5f - ecy) / ry;
                bool inEllipse = (nx * nx) + (ny * ny) <= 1f;
                bool isGreen = pixels[(y * canvas) + x] == green;
                if (inEllipse)
                {
                    area++;
                    if (!isGreen)
                    {
                        holes++;
                    }
                }
                else if (isGreen)
                {
                    outside++;
                }
            }
        }

        Assert.True(area > 1000, $"stand-in ellipse area {area}");
        Assert.True(holes > 20, $"stand-in ellipse holes {holes} outside {outside}");
        Assert.True(outside > 20, $"leaf pixels outside the stand-in ellipse {outside}");
    }

    private static void AssertNear(float x, float y, MarkShape shape)
    {
        MarkFigure figure = Assert.Single(shape.Figures);
        Assert.NotEmpty(figure.Segs);
        Assert.InRange(figure.StartX, x - 0.02f, x + 0.02f);
        Assert.InRange(figure.StartY, y - 0.02f, y + 0.02f);
    }

    private static int Cubics(MarkShape shape) => shape.Figures.Sum(figure => figure.Segs.Count(seg => !seg.IsLine));

    private static int Lines(MarkShape shape) => shape.Figures.Sum(figure => figure.Segs.Count(seg => seg.IsLine));

    private static (float X, float Y) UniqueInterior(MarkShape[] shapes, int index)
    {
        (float minX, float minY, float maxX, float maxY) = Bounds(shapes[index]);
        List<(float X, float Y)> hits = [];
        for (float y = minY; y <= maxY; y += 6f)
        {
            for (float x = minX; x <= maxX; x += 6f)
            {
                if (Exclusive(shapes, index, x, y))
                {
                    hits.Add((x, y));
                }
            }
        }

        Assert.NotEmpty(hits);
        (float bestX, float bestY) = hits[0];
        int bestNeighbors = -1;
        foreach ((float x, float y) in hits)
        {
            int neighbors = 0;
            foreach ((float ox, float oy) in hits)
            {
                float dx = ox - x;
                float dy = oy - y;
                if ((dx * dx) + (dy * dy) <= 36f)
                {
                    neighbors++;
                }
            }

            if (neighbors > bestNeighbors)
            {
                bestNeighbors = neighbors;
                bestX = x;
                bestY = y;
            }
        }

        return (bestX, bestY);
    }

    private static bool Exclusive(MarkShape[] shapes, int index, float x, float y)
    {
        for (int i = 0; i < shapes.Length; i++)
        {
            bool hit = Contains(shapes[i], x, y);
            if (hit != (i == index))
            {
                return false;
            }
        }

        return true;
    }

    private static bool Contains(MarkShape shape, float x, float y)
    {
        foreach (MarkFigure figure in shape.Figures)
        {
            if (Winding(Flatten(figure), x, y) != 0)
            {
                return true;
            }
        }

        return false;
    }

    private static List<(float X, float Y)> Flatten(MarkFigure figure)
    {
        List<(float X, float Y)> pts = [(figure.StartX, figure.StartY)];
        float x = figure.StartX;
        float y = figure.StartY;
        foreach (MarkSeg seg in figure.Segs)
        {
            if (seg.IsLine)
            {
                pts.Add((seg.X, seg.Y));
                x = seg.X;
                y = seg.Y;
                continue;
            }

            for (int step = 1; step <= 12; step++)
            {
                float t = step / 12f;
                float u = 1f - t;
                float uu = u * u;
                float tt = t * t;
                float px = (uu * u * x) + (3f * uu * t * seg.X1) + (3f * u * tt * seg.X2) + (tt * t * seg.X);
                float py = (uu * u * y) + (3f * uu * t * seg.Y1) + (3f * u * tt * seg.Y2) + (tt * t * seg.Y);
                pts.Add((px, py));
            }

            x = seg.X;
            y = seg.Y;
        }

        return pts;
    }

    private static int Winding(List<(float X, float Y)> pts, float x, float y)
    {
        int w = 0;
        for (int i = 0; i < pts.Count; i++)
        {
            (float x0, float y0) = pts[i];
            (float x1, float y1) = pts[(i + 1) % pts.Count];
            float cross = ((x1 - x0) * (y - y0)) - ((x - x0) * (y1 - y0));
            if (y0 <= y)
            {
                if (y1 > y && cross > 0)
                {
                    w++;
                }
            }
            else if (y1 <= y && cross < 0)
            {
                w--;
            }
        }

        return w;
    }

    private static (float MinX, float MinY, float MaxX, float MaxY) Bounds(MarkShape shape)
    {
        float minX = float.PositiveInfinity;
        float minY = float.PositiveInfinity;
        float maxX = float.NegativeInfinity;
        float maxY = float.NegativeInfinity;
        foreach (MarkFigure figure in shape.Figures)
        {
            Include(ref minX, ref minY, ref maxX, ref maxY, figure.StartX, figure.StartY);
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

        return (minX, minY, maxX, maxY);
    }

    private static void Include(ref float minX, ref float minY, ref float maxX, ref float maxY, float x, float y)
    {
        minX = MathF.Min(minX, x);
        minY = MathF.Min(minY, y);
        maxX = MathF.Max(maxX, x);
        maxY = MathF.Max(maxY, y);
    }
}
