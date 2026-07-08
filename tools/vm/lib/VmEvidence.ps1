#Requires -Version 7.6
# Dot-sourced by WinMint-VmConsole.ps1 — not a standalone entrypoint.
function New-WinMintVmSetupShellWatch {
    [ordered]@{
        phasesSeen = @()
        liveUi = $false
        desktopGuard = $false
        screenshotCaptured = $false
        screenshotPath = ''
    }
}

function Register-WinMintVmSetupShellWatchSample {
    param(
        [Parameter(Mandatory)]$Watch,
        $GuestSnapshot
    )

    if (-not $GuestSnapshot) { return }
    $phase = [string]$GuestSnapshot.setupPhase
    if ($phase -and $Watch.phasesSeen -notcontains $phase) {
        $Watch.phasesSeen += $phase
    }
    if ($phase -in @('running', 'finishing')) {
        $Watch.liveUi = $true
    }
    elseif ($GuestSnapshot.setupShellProcessRunning) {
        $Watch.liveUi = $true
    }
    if ($GuestSnapshot.desktopGuardActive) {
        $Watch.desktopGuard = $true
    }
}

function Import-WinMintVmSetupShellWatch {
    param(
        [Parameter(Mandatory)]$Watch,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Watch }
    try {
        $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($saved.PSObject.Properties['phasesSeen']) {
            $Watch.phasesSeen = @($saved.phasesSeen | ForEach-Object { [string]$_ })
        }
        foreach ($name in @('liveUi', 'desktopGuard', 'screenshotCaptured')) {
            if ($saved.PSObject.Properties[$name]) { $Watch[$name] = [bool]$saved.$name }
        }
        if ($saved.PSObject.Properties['screenshotPath']) {
            $Watch.screenshotPath = [string]$saved.screenshotPath
        }
    }
    catch { }
    return $Watch
}

function Save-WinMintVmSetupShellWatch {
    param(
        [Parameter(Mandatory)]$Watch,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    ([ordered]@{
            phasesSeen = @($Watch.phasesSeen)
            liveUi = [bool]$Watch.liveUi
            desktopGuard = [bool]$Watch.desktopGuard
            screenshotCaptured = [bool]$Watch.screenshotCaptured
            screenshotPath = [string]$Watch.screenshotPath
        } | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-WinMintSetupShellAcceptanceEvidence {
    param(
        [Parameter(Mandatory)]$Watch,
        [Parameter(Mandatory)][string]$EvidenceDir,
        [ValidateSet('Full', 'Smoke', 'Auto')]
        [string]$AcceptanceTier = 'Full'
    )

    $plumbingFailures = [System.Collections.Generic.List[string]]::new()
    $evidenceFailures = [System.Collections.Generic.List[string]]::new()
    $meta = [ordered]@{
        phasesSeen = @($Watch.phasesSeen)
        liveUi = [bool]$Watch.liveUi
        desktopGuard = [bool]$Watch.desktopGuard
        screenshotPath = [string]$Watch.screenshotPath
    }

    $firstLogonLog = Get-ChildItem -LiteralPath $EvidenceDir -Recurse -File -Filter 'FirstLogon.log' -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -First 1
    $setupShellLog = Get-ChildItem -LiteralPath $EvidenceDir -Recurse -File -Filter 'SetupShell.log' -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -First 1
    $shellControl = Get-ChildItem -LiteralPath $EvidenceDir -Recurse -File -Filter 'setup-shell-control.json' -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -First 1

    $nativeLogOk = $false
    $controlPhaseComplete = $false

    if (-not $firstLogonLog) {
        $plumbingFailures.Add('FirstLogon.log was not pulled into evidence.') | Out-Null
    }
    else {
        $firstLogonText = Get-Content -LiteralPath $firstLogonLog.FullName -Raw
        if ($firstLogonText -notmatch '(?i)host-start presenter=native|Started WinMint setup shell') {
            if (-not $nativeLogOk) {
                $plumbingFailures.Add('FirstLogon.log does not show the setup shell host starting.') | Out-Null
            }
        }
        if ($firstLogonText -match '(?i)AgentMode\s*=\s*Headless|WINMINT_FIRSTLOGON_MODE=headless') {
            $plumbingFailures.Add('FirstLogon ran headless; OOBE splash path was bypassed.') | Out-Null
        }
    }
    if (-not $setupShellLog) {
        $plumbingFailures.Add('SetupShell.log was not pulled into evidence.') | Out-Null
    }
    else {
        $setupShellText = Get-Content -LiteralPath $setupShellLog.FullName -Raw
        if ($setupShellText -match 'host=native') {
            $nativeLogOk = $true
        }
        else {
            $plumbingFailures.Add('SetupShell.log does not contain host=native marker from WinMintSetupShell host.') | Out-Null
        }
        if ($setupShellText -match 'presenter=gdi-fallback') {
            $meta.presenterPath = 'gdi-fallback'
        }
        elseif ($setupShellText -match 'render ready') {
            $meta.presenterPath = 'd2d'
        }
        elseif ($setupShellText -match 'host=native') {
            $meta.presenterPath = 'native'
        }
    }
    if ($shellControl) {
        try {
            $control = Get-Content -LiteralPath $shellControl.FullName -Raw | ConvertFrom-Json
            $meta.finalPhase = [string]$control.phase
            $controlPhaseComplete = ([string]$control.phase -eq 'complete')
            if (-not $controlPhaseComplete) {
                $plumbingFailures.Add("Setup shell control phase was '$($control.phase)', expected 'complete'.") | Out-Null
            }
        }
        catch {
            $plumbingFailures.Add('setup-shell-control.json could not be parsed from evidence.') | Out-Null
        }
    }
    else {
        $plumbingFailures.Add('setup-shell-control.json was not pulled into evidence.') | Out-Null
    }

    $evidenceBackedShell = $nativeLogOk -and $controlPhaseComplete
    if (-not $Watch.liveUi -and 'running' -notin @($Watch.phasesSeen)) {
        if (-not $evidenceBackedShell) {
            $plumbingFailures.Add('Setup shell UI was not observed running during FirstLogon (live poll).') | Out-Null
        }
    }
    if (-not $Watch.desktopGuard) {
        if (-not $evidenceBackedShell) {
            $evidenceFailures.Add('Desktop guard (NoWinKeys / taskbar hide) was not observed while setup shell was active.') | Out-Null
        }
    }

    foreach ($guestShot in @(
            (Join-Path $EvidenceDir 'LocalAppData-WinMint\Logs\winmint-setup-shell-guest.png')
            (Join-Path $EvidenceDir 'guest-temp\winmint-setup-shell-guest.png')
            (Join-Path $EvidenceDir 'guest-temp\winmint-oobe-capture.png')
        )) {
        if (-not $Watch.screenshotCaptured -and (Test-Path -LiteralPath $guestShot -PathType Leaf)) {
            $dest = Join-Path $EvidenceDir 'oobe-splash.png'
            Copy-Item -LiteralPath $guestShot -Destination $dest -Force
            $Watch.screenshotCaptured = $true
            $Watch.screenshotPath = $dest
            $meta.screenshotPath = $dest
            $meta.screenshotSource = 'guest-evidence-pull'
            break
        }
    }

    if (-not $Watch.screenshotCaptured -or -not (Test-Path -LiteralPath ([string]$Watch.screenshotPath) -PathType Leaf)) {
        $fallbackShot = Join-Path $EvidenceDir 'oobe-splash.png'
        if (Test-Path -LiteralPath $fallbackShot -PathType Leaf) {
            $Watch.screenshotCaptured = $true
            $Watch.screenshotPath = $fallbackShot
            $meta.screenshotPath = $fallbackShot
        }
    }

    $screenshotOk = $false
    if ($Watch.screenshotCaptured -and (Test-Path -LiteralPath ([string]$Watch.screenshotPath) -PathType Leaf)) {
        $shot = Get-Item -LiteralPath ([string]$Watch.screenshotPath)
        if ($shot.Length -lt 8192) {
            $evidenceFailures.Add('OOBE splash screenshot is too small to be a valid desktop capture.') | Out-Null
        }
        else {
            $screenshotOk = $true
            $meta.screenshotBytes = $shot.Length
        }
    }

    if (-not $screenshotOk) {
        $smokeWaive = ($AcceptanceTier -eq 'Smoke') -and
            $nativeLogOk -and
            $controlPhaseComplete -and
            [bool]$Watch.liveUi -and
            ($plumbingFailures.Count -eq 0) -and
            -not (Test-Path -LiteralPath (Join-Path $EvidenceDir 'LocalAppData-WinMint\Logs\winmint-setup-shell-guest.png') -PathType Leaf) -and
            -not (Test-Path -LiteralPath (Join-Path $EvidenceDir 'guest-temp\winmint-setup-shell-guest.png') -PathType Leaf)
        if ($smokeWaive) {
            $meta.screenshotWaived = $true
            $meta.screenshotWaiveReason = 'Smoke tier: native shell logs and control.phase=complete; guest PNG and PrintWindow capture are best-effort only.'
        }
        else {
            $evidenceFailures.Add('OOBE splash screenshot was not captured during setup shell display.') | Out-Null
        }
    }

    $plumbingOk = ($plumbingFailures.Count -eq 0)
    $evidenceOk = ($evidenceFailures.Count -eq 0)

    return [pscustomobject]@{
        ok = ($plumbingOk -and $evidenceOk)
        plumbingOk = $plumbingOk
        evidenceOk = $evidenceOk
        plumbingFailures = @($plumbingFailures)
        evidenceFailures = @($evidenceFailures)
        failures = @($plumbingFailures + $evidenceFailures)
        meta = $meta
    }
}
