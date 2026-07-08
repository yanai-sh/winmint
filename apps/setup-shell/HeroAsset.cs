using Vortice.Direct2D1;
using Vortice.Mathematics;

namespace WinMintSetupShell;

internal sealed class HeroAsset : IDisposable
{
    public ID2D1Bitmap Bitmap { get; }
    public Rect ContentSrc { get; }

    public HeroAsset(ID2D1Bitmap bitmap, Rect contentSrc)
    {
        Bitmap = bitmap;
        ContentSrc = contentSrc;
    }

    public void Dispose() => Bitmap.Dispose();
}
