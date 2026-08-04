#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline optional-feature disable — param-only; no Profile branching.
# Already-Disabled ⇒ ok + digest Disabled. Uses dism.exe.
$mountDir = $Parameters['mountDir']
$featureNames = $Parameters['featureNames']
$workDir = $Parameters['workDirectory']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($featureNames)) { throw 'featureNames required' }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }

$ids = @(
    $featureNames.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ids.Count -eq 0) { throw 'featureNames empty after split' }

$logDir = Join-Path $workDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$dismLog = Join-Path $logDir 'disable-optional-features.dism.log'
$digestPath = Join-Path $logDir 'disable-optional-features.digests.json'
$beforePath = Join-Path $logDir 'optional-features.before.txt'
$afterPath = Join-Path $logDir 'optional-features.after.txt'

function Get-FeatureStateMap {
    param([string] $Path)
    $text = & dism.exe /English /Image:$Path /Get-Features 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dism Get-Features failed: $LASTEXITCODE`n$text"
    }
    $map = @{}
    $cur = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^Feature Name\s*:\s*(.+)\s*$') {
            $cur = $Matches[1].Trim()
        }
        elseif ($null -ne $cur -and $line -match '^State\s*:\s*(.+)\s*$') {
            $map[$cur] = $Matches[1].Trim()
            $cur = $null
        }
    }
    return $map
}

$before = Get-FeatureStateMap -Path $mountDir
$before.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $beforePath -Encoding utf8

foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $before[$id]
    if (-not $state) {
        throw "Optional feature '$id' not found on image"
    }
    if ($state -ieq 'Disabled' -or $state -ieq 'DisabledWithPayloadRemoved') {
        Write-Output "FeatureAlreadyDisabled=$id"
        continue
    }

    $out = & dism.exe /English /Image:$mountDir /Disable-Feature /FeatureName:$id /LogPath:$dismLog 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dism Disable-Feature failed for '$id': $LASTEXITCODE`n$out"
    }
    Write-Output "FeatureDisabled=$id"
}

$after = Get-FeatureStateMap -Path $mountDir
$after.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
    Set-Content -LiteralPath $afterPath -Encoding utf8

$digests = [ordered]@{}
foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $after[$id]
    if ($state -ieq 'Disabled' -or $state -ieq 'DisabledWithPayloadRemoved') {
        $digests["disabled.feature.$id"] = 'Disabled'
    }
    else {
        throw "Optional feature '$id' not Disabled after disable (state=$state)"
    }
}
$digests | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8

Write-Output "DisableOptionalFeatures ok count=$($ids.Count)"
exit 0
