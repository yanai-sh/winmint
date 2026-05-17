#Requires -Version 7.3
<#
<summary>
    Fast UI fixture run for WinWS (semantic snapshots, not PNG-first).

    Launches WinMint-UI.ps1 -FixtureMode, drives pages via Drive-Ui.ps1, and writes
    output/ui-snapshots JSON plus per-label .ui.json copies under output/ui-audit
    with audit.json (schema winws.uiFixtureAudit.v2). Use WinMint-UI.ps1 -Audit for
    the full audit sweep.
</summary>
#>

[CmdletBinding()]
param(
    [int]$StartupTimeoutSec = 15,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot       = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$drive          = Join-Path $repoRoot 'scripts\ui-automation\Drive-Ui.ps1'
$ui             = Join-Path $repoRoot 'WinMint-UI.ps1'
$shotDir        = Join-Path $repoRoot 'output\screenshots'
$snapshotsDir    = Join-Path $repoRoot 'output\ui-snapshots'
$fixturePwshExe  = (Get-Process -Id $PID).Path
$auditDir = Join-Path $repoRoot ("output\ui-audit\fixture-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:FixtureHwnd = 0
$script:AuditStates = [System.Collections.Generic.List[object]]::new()

if (-not ('WinWS.UiFixtureWindowNative' -as [Type])) {
    Add-Type -Namespace WinWS -Name UiFixtureWindowNative -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(
            System.IntPtr hWnd,
            System.IntPtr hWndInsertAfter,
            int X,
            int Y,
            int cx,
            int cy,
            uint uFlags);
'@
}

function Invoke-Drive {
    param([Parameter(Mandatory)][string[]]$Args)
    $driveArgs = @($Args)
    if ($script:FixtureHwnd -ne 0 -and $driveArgs -notcontains '-Hwnd') {
        $driveArgs += @('-Hwnd', ([string]$script:FixtureHwnd))
    }
    $output = & $fixturePwshExe -NoProfile -File $drive @driveArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw "Drive-Ui.ps1 failed ($exit): $($driveArgs -join ' ')`n$output"
    }
    $line = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })[-1]
    return $line | ConvertFrom-Json
}

function Wait-ForFixtureWindow {
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
    do {
        Start-Sleep -Milliseconds 400
        try {
            $state = Invoke-Drive -Args @('-Action', 'GetUiState')
            if ($state.ok -and $state.isoVerified) { return $state }
        } catch {}
    } while ((Get-Date) -lt $deadline)
    throw "WinWS fixture window was not ready within ${StartupTimeoutSec}s."
}

function Send-FixtureWindowBehind {
    param([Parameter(Mandatory)][Int64]$Hwnd)

    $handle = [IntPtr]$Hwnd
    if ($handle -eq [IntPtr]::Zero) { return }

    # SW_SHOWNOACTIVATE makes a minimized WPF window renderable for PrintWindow
    # while preserving the user's current foreground app. HWND_BOTTOM keeps the
    # fixture out of the way for interactive desktop work.
    $null = [WinWS.UiFixtureWindowNative]::ShowWindow($handle, 4)
    Start-Sleep -Milliseconds 200

    $hwndBottom     = [IntPtr]1
    $swpNoSize      = 0x0001
    $swpNoMove      = 0x0002
    $swpNoActivate  = 0x0010
    $flags = [uint32]($swpNoSize -bor $swpNoMove -bor $swpNoActivate)
    $null = [WinWS.UiFixtureWindowNative]::SetWindowPos($handle, $hwndBottom, 0, 0, 0, 0, $flags)
    Start-Sleep -Milliseconds 200
}

function Capture-State {
    param(
        [Parameter(Mandatory)][string]$Label,
        [int]$Page = -1
    )
    if ($Page -ge 0) {
        $nav = Invoke-Drive -Args @('-Action', 'GoToPage', '-Page', ([string]$Page))
        if ([int]$nav.reached -ne $Page) {
            throw "Expected page $Page for '$Label', reached $($nav.reached)."
        }
    }
    Start-Sleep -Milliseconds 350
    $snapshot = Invoke-Drive -Args @('-Action', 'Snapshot', '-Label', $Label)
    $semanticSrc = [string]$snapshot.semantic
    if (-not (Test-Path -LiteralPath $semanticSrc)) {
        throw "Snapshot did not produce semantic file: $semanticSrc"
    }
    $uiSnapName = "$Label.ui.json"
    $auditUiPath = Join-Path $auditDir $uiSnapName
    Copy-Item -LiteralPath $semanticSrc -Destination $auditUiPath -Force

    $pngName = $null
    if ($null -ne $snapshot.png -and (Test-Path -LiteralPath ([string]$snapshot.png))) {
        $pngName = [System.IO.Path]::GetFileName([string]$snapshot.png)
        Copy-Item -LiteralPath ([string]$snapshot.png) -Destination (Join-Path $auditDir $pngName) -Force
    }

    $script:AuditStates.Add([pscustomobject]@{
        id         = $Label
        page       = [int]$snapshot.page
        uiSnapshot = $uiSnapName
        png        = $pngName
    }) | Out-Null
    Write-Host "captured: $Label"
}

function Set-Text {
    param([string]$Name, [string]$Value)
    Invoke-Drive -Args @('-Action', 'SetText', '-Name', $Name, '-Value', $Value) | Out-Null
}

function Click-Control {
    param([string]$Name)
    Invoke-Drive -Args @('-Action', 'Click', '-Name', $Name) | Out-Null
    Start-Sleep -Milliseconds 180
}

Write-Host "=== Fast UI fixture captures ===" -ForegroundColor Cyan
$null = New-Item -ItemType Directory -Path $shotDir -Force
$null = New-Item -ItemType Directory -Path $auditDir -Force

if (Test-Path -LiteralPath $snapshotsDir) {
    Get-ChildItem -LiteralPath $snapshotsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Get-ChildItem -LiteralPath $shotDir -Filter 'fixture-*.png' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$fixtureStdout = Join-Path $shotDir 'fixture-ui-stdout.log'
$fixtureStderr = Join-Path $shotDir 'fixture-ui-stderr.log'
Remove-Item -LiteralPath $fixtureStdout,$fixtureStderr -Force -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath $fixturePwshExe `
    -ArgumentList @('-STA', '-NoProfile', '-File', $ui, '-FixtureMode') `
    -WorkingDirectory $repoRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $fixtureStdout `
    -RedirectStandardError $fixtureStderr `
    -PassThru

try {
    $state = Wait-ForFixtureWindow
    Write-Host "fixture ready: page=$($state.page) isoVerified=$($state.isoVerified)"
    $windowInfo = Invoke-Drive -Args @('-Action', 'GetWindowInfo')
    $script:FixtureHwnd = [int64]$windowInfo.hwnd
    Send-FixtureWindowBehind -Hwnd ([int64]$windowInfo.hwnd)

    Capture-State -Label 'fixture-page0-source' -Page 0

    Capture-State -Label 'fixture-page1-machine-defaults' -Page 1
    Invoke-Drive -Args @('-Action', 'SetDriverFixture') | Out-Null
    Capture-State -Label 'fixture-page1-machine-custom-driver'

    Capture-State -Label 'fixture-page2-disk-defaults' -Page 2
    Click-Control -Name 'RbDiskAuto'
    Capture-State -Label 'fixture-page2-disk-auto-erase'
    Invoke-Drive -Args @('-Action', 'SetCheck', '-Name', 'ChkDiskWipeConfirm', '-Value', 'true') | Out-Null
    Capture-State -Label 'fixture-page2-disk-auto-erase-confirmed'

    Capture-State -Label 'fixture-page3-identity-passwordless' -Page 3
    Set-Text -Name 'TxtComputerName' -Value 'WINWS-LAB-PC'
    Set-Text -Name 'TxtAccountName' -Value 'yanai'
    Capture-State -Label 'fixture-page3-identity-filled'

    Capture-State -Label 'fixture-page4-workstation-defaults' -Page 4
    Click-Control -Name 'ChkShellWindhawk'
    Click-Control -Name 'ChkShellYasb'
    Click-Control -Name 'ChkShellKomorebi'
    Click-Control -Name 'ChkWslDebian'
    Click-Control -Name 'ChkWslArch'
    Click-Control -Name 'ChkWslFedora'
    Click-Control -Name 'ChkEditorZed'
    Capture-State -Label 'fixture-page4-workstation-expanded'

    Capture-State -Label 'fixture-page5-launch' -Page 5

    Write-Host "=== Done. Fixture captures in $shotDir ===" -ForegroundColor Cyan
    $audit = [ordered]@{
        schema    = 'winws.uiFixtureAudit.v2'
        mode      = 'fixture'
        started   = (Get-Date).ToString('o')
        screenshotDir = $shotDir
        auditDir  = $auditDir
        states    = @($script:AuditStates)
        summary   = @{
            status = 'pass'
            count  = $script:AuditStates.Count
        }
    }
    $auditPath = Join-Path $auditDir 'audit.json'
    $audit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $auditPath -Encoding UTF8
    Write-Host "audit: $auditPath"
    Get-ChildItem -LiteralPath $auditDir -Filter '*.ui.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { Write-Host "  $($_.FullName)" }
} catch {
    if ($null -ne $proc -and $proc.HasExited) {
        Write-Warning "Fixture UI process exited with code $($proc.ExitCode)."
    }
    foreach ($log in @($fixtureStderr, $fixtureStdout)) {
        if (Test-Path -LiteralPath $log) {
            Write-Warning "Last lines from $log"
            Get-Content -LiteralPath $log -Tail 40 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Warning "  $_" }
        }
    }
    throw
} finally {
    if (-not $KeepOpen) {
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -in @('pwsh.exe','powershell.exe') -and
                $_.CommandLine -match 'WinMint-UI.ps1' -and
                $_.CommandLine -match 'FixtureMode'
            } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        if ($null -ne $proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
