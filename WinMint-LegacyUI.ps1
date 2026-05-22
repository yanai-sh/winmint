#Requires -Version 7.3

<#
<summary>
    WinMint — WPF GUI front-end.
    Replaces the Spectre.Console terminal wizard in WinMint-CLI.ps1.
    Collects settings into a WinMint build profile and passes that profile to the build engine.
</summary>
<description>
    Cinematic WPF UI from apps\legacy-wpf\Views\MainWindow.xaml (requires x:Name="StageStart").
    Optional vendored WPF UI (Mica / FluentWindow). Auto-elevates via UAC — DISM needs admin for ISO metadata and builds.
    Run: pwsh -NoProfile -File WinMint-LegacyUI.ps1

    Diagnostics:
    - Live transcript per process: %LOCALAPPDATA%\\WinMint\\logs\\WinMint-UI-pid<PID>.txt; mirrored to WinMint-UI-last.txt when the session ends
    - Structured JSONL (optional): WinMint-UI-events.jsonl — disable with WINMINT_UI_NO_JSONL=1
    - Last crash details: WinMint-UI-last-crash.txt, WinMint-UI-wpf-crash.txt, WinMint-UI-appdomain-unhandled.txt, WinMint-UI-unobserved-task.txt
    - On any fatal error the console stays open until you press Enter.
    - Optional: WINMINT_UI_WAIT_FOR_ELEVATED_CHILD=1 makes the pre-UAC shell wait for the elevated child exit code.
</description>
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ExportHostDrivers,
    [switch]$SelfElevated,  # internal — set by Invoke-SelfElevate; do not pass manually
    [string]$ResumeProfile = '',  # internal — path to a pre-built profile JSON; skips wizard
    [switch]$FixtureMode # test-only — seeds fixture UI state without ISO verification
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 2.0

. "$PSScriptRoot\src\engine\Core.ps1"
. (Get-WinMintPath -Name LegacyUiApp -ChildPath 'Bootstrap\Logging.ps1')
Initialize-WinMintUiLogging
Register-WinMintUiProcessFaultHandlers

$_t0 = [System.Diagnostics.Stopwatch]::StartNew()
function _T { param([string]$label) Write-WinMintUiLog -Level TRACE -Source 'bootstrap' -Message ('{0}ms {1}' -f [int]$_t0.Elapsed.TotalMilliseconds, $label) }

function Start-WinMintUiSessionTranscript {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    try {
        $dir = Get-WinMintUiLogDirectory
        # Per-PID path avoids "file in use" when a parent pwsh still has Start-Transcript open
        # (STA relaunch, elevation waiter, or a second WinMint-UI instance).
        $script:WinMintUiSessionTranscriptPath = Join-Path $dir ("WinMint-UI-pid{0}.txt" -f $PID)
        Start-Transcript -LiteralPath $script:WinMintUiSessionTranscriptPath -Force -IncludeInvocationHeader | Out-Null
        Write-Host "WinMint-UI transcript: $($script:WinMintUiSessionTranscriptPath)" -ForegroundColor DarkGray
    } catch {
        Write-WinMintUiLog -Level WARN -Source 'transcript' -Message "Transcript unavailable: $($_.Exception.Message)"
        $script:WinMintUiSessionTranscriptPath = $null
    }
}

function Stop-WinMintUiSessionTranscript {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    try {
        $src = $script:WinMintUiSessionTranscriptPath
        if (-not [string]::IsNullOrWhiteSpace($src) -and (Test-Path -LiteralPath $src)) {
            $dst = Join-Path (Get-WinMintUiLogDirectory) 'WinMint-UI-last.txt'
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    } catch {}
    $script:WinMintUiSessionTranscriptPath = $null
}

function Invoke-WinMintUiPauseAfterFault {
    param([string]$Headline)
    Write-WinMintUiLog -Level ERROR -Source 'fault' -Message $Headline
    Write-Host "`n--- $Headline ---`n" -ForegroundColor Red
    Stop-WinMintUiSessionTranscript
    Read-Host 'Press Enter to close this window'
}

function Stop-WinMintUiRegionalPrefetchJob {
    if ($null -eq $script:RegionalRefreshJob) { return }
    try {
        if ($script:RegionalRefreshJob.State -eq 'Running') {
            Stop-Job -Job $script:RegionalRefreshJob -ErrorAction SilentlyContinue
        }
    } catch {}
    try { Remove-Job -Job $script:RegionalRefreshJob -Force -ErrorAction SilentlyContinue } catch {}
    $script:RegionalRefreshJob = $null
}

trap {
    Stop-WinMintUiRegionalPrefetchJob
    $detail = Format-WinMintUiErrorRecord -InputObject $_ -AsSingleString
    Write-WinMintUiLog -Level CRITICAL -Source 'trap' -Message $_.Exception.Message
    Write-Host $detail -ForegroundColor Red
    Write-WinMintUiCrashDump -Text $detail
    Invoke-WinMintUiPauseAfterFault -Headline 'WinMint-UI failed (PowerShell terminating error)'
    exit 1
}

Start-WinMintUiSessionTranscript
_T 'Script start'

function Get-WinMintUiForwardArgs {
    # Return [string[]] explicitly so Start-Process -ArgumentList binds without
    # ambiguity around PowerShell pipeline unrolling of List<string> outputs.
    $list = [System.Collections.Generic.List[string]]@('-STA', '-NoProfile', '-File', "`"$PSCommandPath`"")
    if ($DryRun)            { $list.Add('-DryRun') }
    if ($ExportHostDrivers) { $list.Add('-ExportHostDrivers') }
    if ($SelfElevated)      { $list.Add('-SelfElevated') }
    if ($ResumeProfile)     { $list.Add('-ResumeProfile'); $list.Add("`"$ResumeProfile`"") }
    if ($FixtureMode)       { $list.Add('-FixtureMode') }
    if ($VerbosePreference -eq 'Continue') { $list.Add('-Verbose') }
    return [string[]]$list
}

# WPF (and OpenFileDialog, Clipboard.GetFileDropList) requires an STA apartment. PS7 defaults to MTA.
# Same-process relaunch also covers the WPF-already-initialized case: the AppContext switch
# Dependencies.ps1 sets is process-wide and cannot be re-applied; both conditions need a fresh process.
$_switchValue = $false
$wpfReinit    = [System.AppContext]::TryGetSwitch(
    'Switch.System.Windows.Controls.DisableDynamicResourceOptimization', [ref]$_switchValue)
$nonSta       = [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA
if ($nonSta -or $wpfReinit) {
    _T ($nonSta ? 'Not STA — relaunching' : 'WPF already initialized in this process — relaunching')
    # Release transcript before the child starts so two pwsh processes never share one transcript file.
    Stop-WinMintUiSessionTranscript
    # Use the actually-running pwsh.exe; the bare name "pwsh" assumes PATH
    # includes it, which isn't guaranteed on a fresh box.
    $relaunch = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList (Get-WinMintUiForwardArgs) -NoNewWindow -Wait -PassThru
    exit $relaunch.ExitCode
}

_T 'Loading Bootstrap'
. (Get-WinMintPath -Name LegacyUiApp -ChildPath 'Bootstrap\Dependencies.ps1')
_T 'Dependencies done'
. (Get-WinMintPath -Name LegacyUiApp -ChildPath 'Bootstrap\Interop.ps1')
_T 'Interop done'
. (Get-WinMintPath -Name LegacyUiApp -ChildPath 'Bootstrap\Elevation.ps1')

# Get-WindowsImage on the offline install.wim requires admin (DISM API access),
# and the build itself needs admin for DISM/registry/disk operations. Elevate at
# launch via UAC so the wizard and build run in the same process.
if (-not $FixtureMode -and -not (Test-IsAdministrator)) {
    _T 'Not elevated — relaunching via UAC'
    Stop-WinMintUiSessionTranscript
    Invoke-SelfElevate -ScriptPath $PSCommandPath -DryRun:$DryRun -ExportHostDrivers:$ExportHostDrivers -ResumeProfile $ResumeProfile -FixtureMode:$FixtureMode
    exit 0
}

Write-WinMintUiLog "Starting WinMint UI from '$PSScriptRoot'"

# Get-WinUserLanguageList (keyboard layout detection) takes 1-3s. Run it in a ThreadJob
# now so it overlaps with the engine dot-source below (~3-5s). Collected after engine loads.
$script:RegionalRefreshJob = Start-ThreadJob {
    try {
        $tips = [System.Collections.Generic.List[string]]::new()
        foreach ($lang in @(Get-WinUserLanguageList -ErrorAction Stop)) {
            foreach ($tip in [string[]]@($lang.InputMethodTips)) {
                if (-not [string]::IsNullOrWhiteSpace($tip) -and -not $tips.Contains($tip.Trim())) {
                    $tips.Add($tip.Trim())
                }
            }
        }
        return $tips.ToArray()
    } catch { return @() }
}

$script:WinMintRepositoryRoot = $PSScriptRoot
$script:UiScriptDir         = $PSScriptRoot
$script:WinMintFixtureMode    = [bool]$FixtureMode

$_winMintLegacyUiRoot = Get-WinMintPath -Name LegacyUiApp
$_mainWindowXamlPath = Join-Path $_winMintLegacyUiRoot 'Views\MainWindow.xaml'
if (-not (Test-Path -LiteralPath $_mainWindowXamlPath)) {
    throw "Missing main window XAML: $_mainWindowXamlPath"
}
$xamlProbe = Get-Content -LiteralPath $_mainWindowXamlPath -Raw
if ($xamlProbe -notmatch 'x:Name="StageStart"') {
    throw 'WinMint UI requires the cinematic shell: MainWindow.xaml must contain x:Name="StageStart". Legacy wizard path was removed.'
}

_T 'Loading app loader'
. (Get-WinMintPath -Name LegacyUiApp -ChildPath 'App\Start-WinMintUI.ps1')
_T 'App loader loaded'
$script:WinMintUiExitCode = 0
try {
    Start-WinMintUIApp `
        -RepositoryRoot $PSScriptRoot `
        -DryRun:$DryRun `
        -FixtureMode:$FixtureMode `
        -ResumeProfile $ResumeProfile
}
catch {
    $detail = Format-WinMintUiErrorRecord -InputObject $_ -AsSingleString
    Write-WinMintUiLog -Level CRITICAL -Source 'Start-WinMintUIApp' -Message $_.Exception.Message
    Write-Host $detail -ForegroundColor Red
    Write-WinMintUiCrashDump -Text $detail
    $script:WinMintUiExitCode = 1
    Invoke-WinMintUiPauseAfterFault -Headline 'WinMint-UI failed (during Start-WinMintUIApp)'
}
finally {
    Stop-WinMintUiRegionalPrefetchJob
    if (Get-Command Get-WinMintUiAppProcessExitCode -ErrorAction SilentlyContinue) {
        $script:WinMintUiExitCode = [Math]::Max([int]$script:WinMintUiExitCode, [int](Get-WinMintUiAppProcessExitCode))
    }
    if (Get-Command Clear-WinMintUiAppContext -ErrorAction SilentlyContinue) {
        Clear-WinMintUiAppContext
    }
    Stop-WinMintUiSessionTranscript
}

exit $script:WinMintUiExitCode
