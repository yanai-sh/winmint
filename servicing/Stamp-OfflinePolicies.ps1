#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline HKLM policy stamps (SOFTWARE + SYSTEM). Param-only — Plan owns which rows.
$mountDir = $Parameters['mountDir']
$workDirectory = $Parameters['workDirectory']
$policySpecs = $Parameters['policySpecs']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($workDirectory)) { throw 'workDirectory required' }
if ([string]::IsNullOrWhiteSpace($policySpecs)) { throw 'policySpecs required' }

$logDir = Join-Path $workDirectory 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$digestPath = Join-Path $logDir 'digests.json'

function Save-DigestMap {
    param([hashtable] $Digests)
    $map = @{}
    if (Test-Path -LiteralPath $digestPath) {
        foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
            $map[[string]$p.Name] = [string]$p.Value
        }
    }
    foreach ($k in $Digests.Keys) { $map[[string]$k] = [string]$Digests[$k] }
    $map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8
}

$rows = @()
foreach ($raw in ($policySpecs -split ';')) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $parts = $raw -split '\|', 5
    if ($parts.Count -ne 5) { throw "malformed policySpecs row: $raw" }
    $rows += [pscustomobject]@{
        Hive   = $parts[0].Trim().ToUpperInvariant()
        SubKey = $parts[1]
        Name   = $parts[2]
        Type   = $parts[3]
        Data   = $parts[4]
    }
}

$digests = @{}
$byHive = $rows | Group-Object -Property Hive
foreach ($group in $byHive) {
    $hiveName = [string]$group.Name
    $fileName = switch ($hiveName) {
        'SOFTWARE' { 'SOFTWARE' }
        'SYSTEM' { 'SYSTEM' }
        default { throw "unsupported hive '$hiveName'" }
    }
    $hivePath = Join-Path $mountDir "Windows\System32\config\$fileName"
    if (-not (Test-Path -LiteralPath $hivePath)) { throw "hive missing: $hivePath" }

    $hiveKey = "HKLM\WinMintPol_$hiveName"
    Write-Output "REG LOAD $hiveKey"
    & reg.exe load $hiveKey $hivePath
    if ($LASTEXITCODE -ne 0) { throw "reg load failed ($hiveName): $LASTEXITCODE" }
    try {
        foreach ($row in $group.Group) {
            $keyPath = "$hiveKey\$($row.SubKey)"
            & reg.exe add $keyPath /v $row.Name /t $row.Type /d $row.Data /f
            if ($LASTEXITCODE -ne 0) {
                throw "reg add failed: hive=$hiveName sub=$($row.SubKey) name=$($row.Name) exit=$LASTEXITCODE"
            }
            $family = if ($row.SubKey -match 'BraveSoftware') { 'brave'
            } elseif ($row.SubKey -match 'OneDrive') { 'onedrive'
            } elseif ($row.SubKey -match 'Device Installer') { 'deviceInstaller'
            } elseif ($row.SubKey -match 'Device Metadata') { 'device'
            } elseif ($row.SubKey -match 'WindowsCopilot') { 'copilot'
            } elseif ($row.SubKey -match 'Session Manager') { 'wpbt'
            } elseif ($row.SubKey -match 'FileSystem' -or $row.Name -eq 'LongPathsEnabled') { 'filesystem'
            } elseif ($row.SubKey -match '\\Dsh' -or $row.SubKey -match 'AllowNewsAndInterests') { 'widgets'
            } elseif ($row.SubKey -match 'AppModelUnlock') { 'developer'
            } elseif ($row.SubKey -match '\\Sudo') { 'sudo'
            } else { 'edge' }
            $digests["policy.$family.$($row.Name)"] = [string]$row.Data
            Write-Output "policy ok: $family.$($row.Name)=$($row.Data)"
        }
    }
    finally {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $hiveKey
        if ($LASTEXITCODE -ne 0) { throw "reg unload failed ($hiveName): $LASTEXITCODE" }
    }
}

Save-DigestMap $digests
Write-Output "StampOfflinePolicies ok ($($rows.Count) rows)"
exit 0
