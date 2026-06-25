#Requires -Version 5.1

function Save-WinMintFirstLogonState {
    param([hashtable]$State)
    $path = Join-Path $logDir 'FirstLogonState.json'
    $tmp = "$path.tmp"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $path -Force
}


function Read-WinMintFirstLogonState {
    $path = Join-Path $logDir 'FirstLogonState.json'
    try {
        if (Test-Path -LiteralPath $path) {
            return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-WinMintFirstLogonError "FirstLogon state read failed: $_"
    }
    return $null
}


function New-WinMintFirstLogonRunState {
    $previous = Read-WinMintFirstLogonState
    $previousAttempts = 0
    try {
        if ($previous -and $previous.PSObject.Properties['attempts']) {
            $previousAttempts = [int]$previous.attempts
        }
    }
    catch { $previousAttempts = 0 }
    @{
        startedAt = Get-Date -Format o
        agentExitCode = $null
        status = 'running'
        attempts = ($previousAttempts + 1)
        maxAttempts = $script:WinMintFirstLogonMaxAttempts
    }
}


function Read-WinMintFirstLogonSetupProfile {
    $setupProfilePath = Join-Path $payloadDir 'WinMintSetupProfile.json'
    try {
        if (Test-Path -LiteralPath $setupProfilePath) {
            return Get-Content -LiteralPath $setupProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    catch {
        Write-WinMintFirstLogonError "Setup profile read failed: $_"
    }
    return $null
}


function Get-WinMintFirstLogonNestedProfileValue {
    param(
        [object]$BuildProfile,
        [string]$Section,
        [string]$Nested,
        [string]$Name,
        $Default = $null
    )

    if (-not $BuildProfile) { return $Default }
    $sectionProp = $BuildProfile.PSObject.Properties[$Section]
    if (-not $sectionProp) { return $Default }
    $nestedProp = $sectionProp.Value.PSObject.Properties[$Nested]
    if (-not $nestedProp) { return $Default }
    $valueProp = $nestedProp.Value.PSObject.Properties[$Name]
    if (-not $valueProp) { return $Default }
    return $valueProp.Value
}


function Invoke-WinMintFirstLogonReg {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $out = & reg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-WinMintFirstLogonError "reg.exe $($Arguments -join ' ') exited $LASTEXITCODE`n$($out | Out-String)"
    }
}


function Set-WinMintFirstLogonRetry {
    # The RunOnce command embeds quoted paths with spaces. reg.exe mangles embedded
    # quotes in a /d value ("ERROR: Invalid syntax"), so write the value with the
    # native registry provider, which stores the string verbatim.
    $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $exe = Resolve-WinMintPowerShellHost
    $command = "`"$exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$script:WinMintFirstLogonEntryPath`""
    if (-not (Test-Path -LiteralPath $runOnce)) { New-Item -Path $runOnce -Force | Out-Null }
    Set-ItemProperty -LiteralPath $runOnce -Name 'WinMintFirstLogonRetry' -Value $command -Type String -Force
}


function Clear-WinMintFirstLogonRetry {
    $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    Remove-ItemProperty -LiteralPath $runOnce -Name 'WinMintFirstLogonRetry' -Force -ErrorAction SilentlyContinue
}


function Clear-WinMintAutoLogonPassword {
    # Removes the plaintext DefaultPassword and AutoLogonCount from the registry.
    # Called ONLY once the agent run fully succeeds. Until then the password must stay
    # resident so auto sign-in survives every install reboot without ever prompting.
    $winlogon = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    foreach ($name in @('DefaultPassword', 'AutoLogonCount')) {
        Invoke-WinMintFirstLogonReg -Arguments @('delete', $winlogon, '/v', $name, '/f') -AllowFailure
    }
}


function Get-WinMintFirstLogonServiceSnapshot {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $start = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name Start -ErrorAction SilentlyContinue).Start
        if (-not $svc) { return [ordered]@{ name = $Name; present = $false; status = ''; start = $start } }
        return [ordered]@{ name = $Name; present = $true; status = [string]$svc.Status; startType = [string]$svc.StartType; start = $start }
    }
    catch {
        return [ordered]@{ name = $Name; present = $false; status = ''; startType = ''; start = $null; error = $_.Exception.Message }
    }
}


function Test-WinMintFirstLogonRetainDiagnosticState {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    if (-not $setupProfile) { return $false }

    return ([string]$setupProfile.profileName -eq 'Hyper-V Test')
}


