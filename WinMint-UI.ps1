#Requires -Version 7.3

<#
<summary>
    Windows Workstation Slim — WPF GUI front-end.
    Replaces the Spectre.Console terminal wizard in WinMint-CLI.ps1.
    Collects settings into a WinWS build profile and passes that profile to the build engine.
</summary>
<description>
    Cinematic WPF UI from src\WinWS.UI\Views\MainWindow.xaml (requires x:Name="StageStart").
    Optional vendored WPF UI (Mica / FluentWindow). Auto-elevates via UAC — DISM needs admin for ISO metadata and builds.
    Run: pwsh -NoProfile -File WinMint-UI.ps1

    Diagnostics:
    - Live transcript per process: %LOCALAPPDATA%\\WinWS\\logs\\WinMint-UI-pid<PID>.txt; mirrored to WinMint-UI-last.txt when the session ends
    - Structured JSONL (optional): WinMint-UI-events.jsonl — disable with WINWS_UI_NO_JSONL=1
    - Last crash details: WinMint-UI-last-crash.txt, WinMint-UI-wpf-crash.txt, WinMint-UI-appdomain-unhandled.txt, WinMint-UI-unobserved-task.txt
    - On any fatal error the console stays open until you press Enter.
    - Optional: WINWS_UI_WAIT_FOR_ELEVATED_CHILD=1 makes the pre-UAC shell wait for the elevated child exit code.
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

. "$PSScriptRoot\src\WinWS.UI\Bootstrap\Logging.ps1"
Initialize-WinWSUiLogging
Register-WinWSUiProcessFaultHandlers

$_t0 = [System.Diagnostics.Stopwatch]::StartNew()
function _T { param([string]$label) Write-WinWSUiLog -Level TRACE -Source 'bootstrap' -Message ('{0}ms {1}' -f [int]$_t0.Elapsed.TotalMilliseconds, $label) }

function Start-WinWSUiSessionTranscript {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    try {
        $dir = Get-WinWSUiLogDirectory
        # Per-PID path avoids "file in use" when a parent pwsh still has Start-Transcript open
        # (STA relaunch, elevation waiter, or a second WinMint-UI instance).
        $script:WinWSUiSessionTranscriptPath = Join-Path $dir ("WinMint-UI-pid{0}.txt" -f $PID)
        Start-Transcript -LiteralPath $script:WinWSUiSessionTranscriptPath -Force -IncludeInvocationHeader | Out-Null
        Write-Host "WinMint-UI transcript: $($script:WinWSUiSessionTranscriptPath)" -ForegroundColor DarkGray
    } catch {
        Write-WinWSUiLog -Level WARN -Source 'transcript' -Message "Transcript unavailable: $($_.Exception.Message)"
        $script:WinWSUiSessionTranscriptPath = $null
    }
}

function Stop-WinWSUiSessionTranscript {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    try {
        $src = $script:WinWSUiSessionTranscriptPath
        if (-not [string]::IsNullOrWhiteSpace($src) -and (Test-Path -LiteralPath $src)) {
            $dst = Join-Path (Get-WinWSUiLogDirectory) 'WinMint-UI-last.txt'
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    } catch {}
    $script:WinWSUiSessionTranscriptPath = $null
}

function Invoke-WinWSUiPauseAfterFault {
    param([string]$Headline)
    Write-WinWSUiLog -Level ERROR -Source 'fault' -Message $Headline
    Write-Host "`n--- $Headline ---`n" -ForegroundColor Red
    Stop-WinWSUiSessionTranscript
    Read-Host 'Press Enter to close this window'
}

function Stop-WinWSUiRegionalPrefetchJob {
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
    Stop-WinWSUiRegionalPrefetchJob
    $detail = Format-WinWSUiErrorRecord -InputObject $_ -AsSingleString
    Write-WinWSUiLog -Level CRITICAL -Source 'trap' -Message $_.Exception.Message
    Write-Host $detail -ForegroundColor Red
    Write-WinWSUiCrashDump -Text $detail
    Invoke-WinWSUiPauseAfterFault -Headline 'WinMint-UI failed (PowerShell terminating error)'
    exit 1
}

Start-WinWSUiSessionTranscript
_T 'Script start'

function Get-WinWSUiForwardArgs {
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
    Stop-WinWSUiSessionTranscript
    # Use the actually-running pwsh.exe; the bare name "pwsh" assumes PATH
    # includes it, which isn't guaranteed on a fresh box.
    $relaunch = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList (Get-WinWSUiForwardArgs) -NoNewWindow -Wait -PassThru
    exit $relaunch.ExitCode
}

_T 'Loading Bootstrap'
. "$PSScriptRoot\src\WinWS.UI\Bootstrap\Dependencies.ps1"
_T 'Dependencies done'
. "$PSScriptRoot\src\WinWS.UI\Bootstrap\Interop.ps1"
_T 'Interop done'
. "$PSScriptRoot\src\WinWS.UI\Bootstrap\Elevation.ps1"

# Get-WindowsImage on the offline install.wim requires admin (DISM API access),
# and the build itself needs admin for DISM/registry/disk operations. Elevate at
# launch via UAC so the wizard and build run in the same process.
if (-not $FixtureMode -and -not (Test-IsAdministrator)) {
    _T 'Not elevated — relaunching via UAC'
    Stop-WinWSUiSessionTranscript
    Invoke-SelfElevate -ScriptPath $PSCommandPath -DryRun:$DryRun -ExportHostDrivers:$ExportHostDrivers -ResumeProfile $ResumeProfile -FixtureMode:$FixtureMode
    exit 0
}

Write-WinWSUiLog "Starting WinWS UI from '$PSScriptRoot'"

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

$script:WinWSRepositoryRoot = $PSScriptRoot
$script:UiScriptDir         = $PSScriptRoot
$script:WinWSFixtureMode    = [bool]$FixtureMode

$_winWSUiRoot = Join-Path $PSScriptRoot 'src\WinWS.UI'
$_mainWindowXamlPath = Join-Path $_winWSUiRoot 'Views\MainWindow.xaml'
if (-not (Test-Path -LiteralPath $_mainWindowXamlPath)) {
    throw "Missing main window XAML: $_mainWindowXamlPath"
}
$xamlProbe = Get-Content -LiteralPath $_mainWindowXamlPath -Raw
if ($xamlProbe -notmatch 'x:Name="StageStart"') {
    throw 'WinWS UI requires the cinematic shell: MainWindow.xaml must contain x:Name="StageStart". Legacy wizard path was removed.'
}

_T 'Loading app loader'
. "$PSScriptRoot\src\WinWS.UI\App\Start-WinWSUI.ps1"
_T 'App loader loaded'
$script:WinWSUiExitCode = 0
try {
    Start-WinWSUIApp `
        -RepositoryRoot $PSScriptRoot `
        -DryRun:$DryRun `
        -FixtureMode:$FixtureMode `
        -ResumeProfile $ResumeProfile
}
catch {
    $detail = Format-WinWSUiErrorRecord -InputObject $_ -AsSingleString
    Write-WinWSUiLog -Level CRITICAL -Source 'Start-WinWSUIApp' -Message $_.Exception.Message
    Write-Host $detail -ForegroundColor Red
    Write-WinWSUiCrashDump -Text $detail
    $script:WinWSUiExitCode = 1
    Invoke-WinWSUiPauseAfterFault -Headline 'WinMint-UI failed (during Start-WinWSUIApp)'
}
finally {
    Stop-WinWSUiRegionalPrefetchJob
    if (Get-Command Get-WinWSUiAppProcessExitCode -ErrorAction SilentlyContinue) {
        $script:WinWSUiExitCode = [Math]::Max([int]$script:WinWSUiExitCode, [int](Get-WinWSUiAppProcessExitCode))
    }
    if (Get-Command Clear-WinWSUiAppContext -ErrorAction SilentlyContinue) {
        Clear-WinWSUiAppContext
    }
    Stop-WinWSUiSessionTranscript
}

exit $script:WinWSUiExitCode
