#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline capability remove — param-only; no Profile branching.
# Already-Absent / not listed ⇒ ok + digest Absent (reuse-media). Uses dism.exe.
# Optional features mirror this posture (Disable-OptionalFeatures.ps1) — not throw-on-missing.
$mountDir = $Parameters['mountDir']
$capabilityNames = $Parameters['capabilityNames']
$workDir = $Parameters['workDirectory']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($capabilityNames)) { throw 'capabilityNames required' }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }

$ids = @(
    $capabilityNames.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ids.Count -eq 0) { throw 'capabilityNames empty after split' }

$logDir = Join-Path $workDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$dismLog = Join-Path $logDir 'remove-capabilities.dism.log'
$digestPath = Join-Path $logDir 'remove-capabilities.digests.json'
$beforePath = Join-Path $logDir 'capabilities.before.txt'
$afterPath = Join-Path $logDir 'capabilities.after.txt'

function Get-CapabilityStateMap {
    param([string] $Path)
    $text = & dism.exe /English /Image:$Path /Get-Capabilities 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dism Get-Capabilities failed: $LASTEXITCODE`n$text"
    }
    $map = @{}
    $cur = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^Capability Identity\s*:\s*(.+)\s*$') {
            $cur = $Matches[1].Trim()
        }
        elseif ($null -ne $cur -and $line -match '^State\s*:\s*(.+)\s*$') {
            $map[$cur] = $Matches[1].Trim()
            $cur = $null
        }
    }
    return $map
}

$before = Get-CapabilityStateMap -Path $mountDir
$before.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $beforePath -Encoding utf8

foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $before[$id]
    if (-not $state) {
        # Not listed on this image — treat as already absent (fail closed would break media churn).
        Write-Output "CapabilityAbsent=$id"
        continue
    }
    if ($state -ieq 'NotPresent' -or $state -ieq 'Absent' -or $state -ieq 'Not Present') {
        Write-Output "CapabilityAlreadyAbsent=$id"
        continue
    }

    $out = & dism.exe /English /Image:$mountDir /Remove-Capability /CapabilityName:$id /LogPath:$dismLog 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dism Remove-Capability failed for '$id': $LASTEXITCODE`n$out"
    }
    Write-Output "CapabilityRemoved=$id"
}

$after = Get-CapabilityStateMap -Path $mountDir
$after.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $afterPath -Encoding utf8

$digests = [ordered]@{}
foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $after[$id]
    if (-not $state -or $state -ieq 'NotPresent' -or $state -ieq 'Absent' -or $state -ieq 'Not Present') {
        $digests["removed.capability.$id"] = 'Absent'
    }
    else {
        throw "Capability '$id' still present after remove (state=$state)"
    }
}
$digests | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8

Write-Output "RemoveCapabilities ok count=$($ids.Count)"
exit 0
