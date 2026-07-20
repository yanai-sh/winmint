using System.Diagnostics;

namespace WinMintSetupShell;

/// <summary>
/// Eases the painted determinate fill toward status.ProgressPct so milestone
/// jumps from JSON look smooth. Never moves the bar backward.
/// </summary>
internal static class ProgressFillAnimator
{
    private static readonly Stopwatch Clock = Stopwatch.StartNew();
    private static double _displayedPct;
    private static long _lastTickMs = -1;
    private static bool _determinate;

    // Higher = snappier catch-up toward the target (~6 ≈ half-life ~115ms).
    private const double Speed = 6.0;

    public static double Resolve(double targetPct, string? progressMode)
    {
        var determinate = string.Equals(progressMode, "determinate", StringComparison.OrdinalIgnoreCase);
        if (!determinate)
        {
            _determinate = false;
            _lastTickMs = -1;
            return 0;
        }

        targetPct = Math.Clamp(targetPct, 0.0, 100.0);
        var now = Clock.ElapsedMilliseconds;

        if (!_determinate || _lastTickMs < 0)
        {
            // Entering determinate: ease up from current painted value (0 after indeterminate).
            _determinate = true;
            _lastTickMs = now;
            if (_displayedPct > targetPct)
            {
                _displayedPct = targetPct;
            }
            return _displayedPct;
        }

        var dt = Math.Clamp((now - _lastTickMs) / 1000.0, 0.0, 0.1);
        _lastTickMs = now;

        if (targetPct <= _displayedPct)
        {
            // Never retreat; snap only at completion so the bar can finish cleanly.
            if (targetPct >= 99.5)
            {
                _displayedPct = targetPct;
            }
            return _displayedPct;
        }

        var alpha = 1.0 - Math.Exp(-Speed * dt);
        _displayedPct += (targetPct - _displayedPct) * alpha;
        if (targetPct - _displayedPct < 0.08)
        {
            _displayedPct = targetPct;
        }

        return _displayedPct;
    }
}
