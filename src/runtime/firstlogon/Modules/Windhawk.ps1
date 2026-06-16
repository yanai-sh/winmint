#Requires -Version 7.6

function Resolve-AgentWindhawkInstallRoot {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Windhawk')) }
    if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Windhawk')) }

    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='Windhawk'" -ErrorAction SilentlyContinue
    if ($svc -and $svc.PathName) {
        $pathName = [string]$svc.PathName
        $exePath = if ($pathName -match '^\s*"([^"]+)"') { $matches[1] } else { ($pathName -split '\s+', 2)[0] }
        if ($exePath -and (Split-Path -Parent $exePath)) {
            $candidates.Add((Split-Path -Parent $exePath))
        }
    }

    foreach ($root in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object {
                $_.PSObject.Properties['DisplayName'] -and
                $_.PSObject.Properties['InstallLocation'] -and
                $_.DisplayName -eq 'Windhawk' -and
                $_.InstallLocation
            } |
            ForEach-Object { $candidates.Add([string]$_.InstallLocation) }
    }

    foreach ($candidate in ($candidates.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'windhawk.exe')) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Invoke-WinMintAgentWindhawkBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$State
    $cfg = if ($AgentProfile.modules -and $AgentProfile.modules.PSObject.Properties['windhawk']) {
        $AgentProfile.modules.windhawk
    } else {
        $null
    }
    if (-not $cfg -or -not [bool]$cfg.enabled) {
        return [pscustomobject]@{
            Id      = 'windhawk'
            Status  = 'skipped'
            Message = 'Windhawk was not selected.'
        }
    }

    $payloadDir = Join-Path $agentRoot 'Assets\Windhawk'
    $restoreScript = Join-Path $payloadDir 'WindhawkBootstrap.ps1'
    $virtualDesktopScript = Join-Path $payloadDir 'DisableVirtualDesktopFlyouts.ps1'
    $presetFile = Join-Path $payloadDir 'preset.json'
    if (-not (Test-Path -LiteralPath $restoreScript)) { throw "Windhawk restore script missing: $restoreScript" }
    if (-not (Test-Path -LiteralPath $virtualDesktopScript)) { throw "Virtual desktop flyout script missing: $virtualDesktopScript" }
    if (-not (Test-Path -LiteralPath $presetFile)) { throw "Windhawk preset missing: $presetFile" }

    $windhawkRoot = Join-Path $env:PROGRAMDATA 'Windhawk'
    $windhawkInstallRoot = Resolve-AgentWindhawkInstallRoot
    $programWindhawk = if ($windhawkInstallRoot) { Join-Path $windhawkInstallRoot 'windhawk.exe' } else { $null }
    $installed = (Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue) -or
        ($programWindhawk -and (Test-Path -LiteralPath $programWindhawk))
    if (-not $installed) {
        Install-AgentManifestTool -ToolId 'windhawk' -State $State
    }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $windhawkInstallRoot = Resolve-AgentWindhawkInstallRoot
        $programWindhawk = if ($windhawkInstallRoot) { Join-Path $windhawkInstallRoot 'windhawk.exe' } else { $null }
        if ((Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue) -or
            ($programWindhawk -and (Test-Path -LiteralPath $programWindhawk))) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'Windhawk did not appear to install within the expected wait window.' }
    if (-not $windhawkInstallRoot) { throw 'Windhawk install path could not be resolved.' }

    $exe = Resolve-AgentPowerShellHost
    Invoke-AgentNative -FilePath $exe -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $restoreScript,
        '-PresetFile', $presetFile,
        '-WindhawkRoot', $windhawkRoot,
        '-WindhawkInstallRoot', $windhawkInstallRoot
    )
    Invoke-AgentNative -FilePath $exe -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $virtualDesktopScript
    )

    [pscustomobject]@{
        Id      = 'windhawk'
        Status  = 'ok'
        Message = 'Windhawk installed with the WinMint preset.'
    }
}

