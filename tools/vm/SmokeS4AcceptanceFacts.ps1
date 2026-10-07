#requires -Version 7.6
Set-StrictMode -Version Latest

# Mirror of WinMint.Contracts.QuietChromeFacts + GuestChrome (asserted by QuietChromeFactsTests).
function Get-WinMintSmokeS4AcceptanceFacts {
    [ordered]@{
        RequiredPhases = @(
            'shell.firstPaint'
            'jobs.workstation.quiet'
            'jobs.wsl.platform.mocked'
            'shell.chrome'
        )
        SplashBeforeSettle = [pscustomobject]@{
            FirstPaintPhase = 'shell.firstPaint'
            SettleBeginPhase  = 'settle.begin'
        }
        DmaOkAnyOf = @(
            ,@('settle.ok')
            ,@('settle.resumeOk', 'checkpoint.resume')
        )
        SetupRegionOkAnyOf = @(
            'settle.deviceRegionOk'
            'settle.deviceRegionRepaired'
        )
        OnlineRemoveSafetyNet = [pscustomobject]@{
            OnlineRemovePhasePattern = 'removed.appx.online.*'
            DeprovisionPhasePattern  = 'deprovisioned.appx.*'
        }
        ExpectedWallpaperPath   = 'C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg'
        ExpectedDevMode         = 1
        ExpectedSudo            = 3
        ExpectedLongPaths       = 1
        ExpectedSpotlightEnabledState = 0
        RequiredStartPinIds     = @('explorer', 'settings', 'terminal')
        RequiredTaskbarPinIds   = @('explorer', 'terminal')
        RequiredQuietDwords     = [ordered]@{
            SearchboxTaskbarMode = 0
            TaskbarDa            = 0
            TaskbarMn            = 0
            ShowTaskViewButton   = 0
            ShowCopilotButton    = 0
        }
        PackageStrictExtraPins  = [ordered]@{
            'Anysphere.Cursor'     = 'cursor'
            'Zen-Team.Zen-Browser' = 'zen-browser'
        }
    } | ForEach-Object { [pscustomobject]$_ }
}
