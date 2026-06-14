#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-WinMintAdministrator {
    try {
        $probeKey = 'HKLM\SOFTWARE\WinMint\ElevationProbe'
        & reg.exe add $probeKey /v Probe /t REG_SZ /d 1 /f *> $null
        if ($LASTEXITCODE -eq 0) {
            & reg.exe delete $probeKey /f *> $null | Out-Null
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

if (-not (Test-WinMintAdministrator)) {
    throw 'Virtual desktop flyout suppression must run elevated.'
}

$registryBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\14'
$featureIds = @('42105254', '42316343', '34508225', '40459297')

Write-Host 'Virtual desktop flyout suppression'

if (-not (Test-Path -LiteralPath $registryBase)) {
    New-Item -Path $registryBase -ItemType Directory -Force | Out-Null
    Write-Host 'Initialized FeatureManagement override priority 14.'
}

foreach ($id in $featureIds) {
    $keyPath = Join-Path $registryBase $id
    if (-not (Test-Path -LiteralPath $keyPath)) {
        New-Item -Path $keyPath -ItemType Directory -Force | Out-Null
    }

    $current = Get-ItemProperty -LiteralPath $keyPath -Name EnabledState -ErrorAction SilentlyContinue
    if ($current -and $current.EnabledState -eq 1) {
        Write-Host "Feature $id already suppressed."
        continue
    }

    New-ItemProperty -LiteralPath $keyPath -Name EnabledState -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -LiteralPath $keyPath -Name EnabledStateOptions -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Host "Feature $id suppressed."
}

Write-Host 'Virtual desktop flyout suppression applied. Sign out or restart to apply it fully.'
