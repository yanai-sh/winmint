# SetupComplete machine-phase module: form-factor-aware power profile.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir,
# $powerFormFactor, $powerDisableHibernationOnDesktop, $powerPlan.

function Test-ScIsLaptopChassis {
    # Win32_SystemEnclosure ChassisTypes codes for portable/laptop/notebook/handheld/tablet/convertible/detachable.
    try {
        $types = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
    }
    catch {
        return $false
    }
    $laptopCodes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    foreach ($t in $types) {
        if ([int]$t -in $laptopCodes) { return $true }
    }
    return $false
}

function Get-ScPowerPlanCatalog {
    [ordered]@{
        Balanced = [ordered]@{
            Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'
            Label = 'Balanced'
        }
        EnergySaver = [ordered]@{
            Guid = 'a1841308-3541-4fab-bc81-f71556f20b4a'
            Label = 'Energy Saver'
        }
        HighPerformance = [ordered]@{
            Guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            Label = 'High Performance'
        }
        UltimatePerformance = [ordered]@{
            Guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
            Label = 'Ultimate Performance'
        }
    }
}

function Get-ScPowerSchemeList {
    param([Parameter(Mandatory)][string]$PowerCfg)

    try {
        return @(& $PowerCfg /list 2>$null)
    }
    catch {
        return @()
    }
}

function Find-ScPowerSchemeGuidByName {
    param(
        [Parameter(Mandatory)][string]$PowerCfg,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($line in @(Get-ScPowerSchemeList -PowerCfg $PowerCfg)) {
        if ([string]$line -notmatch [regex]::Escape($Name)) { continue }
        if ([string]$line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return ''
}

function Resolve-ScUltimatePerformanceGuid {
    param([Parameter(Mandatory)][string]$PowerCfg)

    $existing = Find-ScPowerSchemeGuidByName -PowerCfg $PowerCfg -Name 'Ultimate Performance'
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return [pscustomobject]@{ Guid = $existing; Created = $false }
    }

    $sourceGuid = (Get-ScPowerPlanCatalog).UltimatePerformance.Guid
    $output = @(& $PowerCfg /duplicatescheme $sourceGuid 2>&1)
    $text = ($output -join "`n")
    if ($text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return [pscustomobject]@{ Guid = $Matches[1].ToLowerInvariant(); Created = $true }
    }

    $afterCreate = Find-ScPowerSchemeGuidByName -PowerCfg $PowerCfg -Name 'Ultimate Performance'
    if (-not [string]::IsNullOrWhiteSpace($afterCreate)) {
        return [pscustomobject]@{ Guid = $afterCreate; Created = $true }
    }

    throw "Could not create or resolve Ultimate Performance power scheme. powercfg output: $text"
}

function Resolve-ScPowerPlanActivation {
    param(
        [Parameter(Mandatory)][string]$PowerCfg,
        [Parameter(Mandatory)][string]$Plan
    )

    $catalog = Get-ScPowerPlanCatalog
    if (-not $catalog.Contains($Plan)) {
        throw "Unsupported power plan '$Plan'."
    }

    if ($Plan -eq 'UltimatePerformance') {
        return Resolve-ScUltimatePerformanceGuid -PowerCfg $PowerCfg
    }

    [pscustomobject]@{ Guid = [string]$catalog[$Plan].Guid; Created = $false }
}

function Invoke-ScPowerProfile {
    $selectedPlan = if ([string]::IsNullOrWhiteSpace($powerPlan)) { 'Balanced' } else { [string]$powerPlan }
    $result = [ordered]@{
        formFactor = $powerFormFactor
        effective = ''
        selectedPlan = $selectedPlan
        activePlanGuid = ''
        createdPlan = $false
        actions = @()
        failed = @()
    }
    $effective = $powerFormFactor
    if ($effective -eq 'Auto') {
        $effective = if (Test-ScIsLaptopChassis) { 'Laptop' } else { 'Desktop' }
    }
    $result.effective = $effective
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    if ($effective -eq 'Desktop' -and $powerDisableHibernationOnDesktop) {
        try {
            & $powercfg /hibernate off | Out-Null
            $result.actions += 'hibernate-off'
            Write-ScLog 'Power profile: hibernation disabled (desktop).'
        }
        catch {
            $result.failed += [ordered]@{ action = 'HibernateOff'; error = [string]$_ }
            Write-ScWarn "powercfg hibernate off failed: $_"
        }
    }

    try {
        $activation = Resolve-ScPowerPlanActivation -PowerCfg $powercfg -Plan $selectedPlan
        $guid = [string]$activation.Guid
        & $powercfg /setactive $guid | Out-Null
        $result.activePlanGuid = $guid
        $result.createdPlan = [bool]$activation.Created
        $result.actions += "plan-$selectedPlan"
        if ([bool]$activation.Created) {
            $result.actions += 'plan-created'
        }
        Write-ScLog "Power profile: $selectedPlan plan activated."
    }
    catch {
        $result.failed += [ordered]@{ action = 'SetActivePlan'; plan = $selectedPlan; error = [string]$_ }
        Write-ScError "powercfg setactive failed for ${selectedPlan}: $_"
    }

    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir 'SetupComplete_Power.json') -Encoding UTF8
}
