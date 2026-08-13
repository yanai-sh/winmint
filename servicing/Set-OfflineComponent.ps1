#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline capability remove OR optional-feature disable — param-only.
# kind=capability|feature. Already-absent/disabled / not listed ⇒ ok + digest.
$kind = [string]$Parameters['kind']
$mountDir = $Parameters['mountDir']
$workDir = $Parameters['workDirectory']
$namesKey = if ($kind -eq 'feature') { 'featureNames' } else { 'capabilityNames' }
$names = $Parameters[$namesKey]
if ($kind -ne 'capability' -and $kind -ne 'feature') { throw "kind must be capability|feature (got '$kind')" }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($names)) { throw "$namesKey required" }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }

$ids = @(
    $names.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ids.Count -eq 0) { throw "$namesKey empty after split" }

$logDir = Join-Path $workDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$dismLog = Join-Path $logDir ("mutate-{0}.dism.log" -f $kind)
$digestPath = Join-Path $logDir 'digests.json'

function Get-StateMap {
    param([string] $Path, [string] $Kind)
    if ($Kind -eq 'capability') {
        $text = & dism.exe /English /Image:$Path /Get-Capabilities 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "dism Get-Capabilities failed: $LASTEXITCODE`n$text" }
        $idRe = '^Capability Identity\s*:\s*(.+)\s*$'
    }
    else {
        $text = & dism.exe /English /Image:$Path /Get-Features 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "dism Get-Features failed: $LASTEXITCODE`n$text" }
        $idRe = '^Feature Name\s*:\s*(.+)\s*$'
    }
    $map = @{}
    $cur = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match $idRe) {
            $cur = $Matches[1].Trim()
        }
        elseif ($null -ne $cur -and $line -match '^State\s*:\s*(.+)\s*$') {
            $map[$cur] = $Matches[1].Trim()
            $cur = $null
        }
    }
    return $map
}

function Save-DigestMap([hashtable] $New) {
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $digestPath) {
        foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
            $map[$p.Name] = [string]$p.Value
        }
    }
    foreach ($k in $New.Keys) { $map[$k] = [string]$New[$k] }
    $map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8
}

$before = Get-StateMap -Path $mountDir -Kind $kind

foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $before[$id]
    if ($kind -eq 'capability') {
        if (-not $state) { Write-Output "CapabilityAbsent=$id"; continue }
        if ($state -ieq 'NotPresent' -or $state -ieq 'Absent' -or $state -ieq 'Not Present') {
            Write-Output "CapabilityAlreadyAbsent=$id"; continue
        }
        $out = & dism.exe /English /Image:$mountDir /Remove-Capability /CapabilityName:$id /LogPath:$dismLog 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "dism Remove-Capability failed for '$id': $LASTEXITCODE`n$out" }
        Write-Output "CapabilityRemoved=$id"
    }
    else {
        if (-not $state) { Write-Output "FeatureAbsent=$id"; continue }
        if ($state -ieq 'Disabled' -or $state -ieq 'DisabledWithPayloadRemoved') {
            Write-Output "FeatureAlreadyDisabled=$id"; continue
        }
        $out = & dism.exe /English /Image:$mountDir /Disable-Feature /FeatureName:$id /LogPath:$dismLog 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "dism Disable-Feature failed for '$id': $LASTEXITCODE`n$out" }
        Write-Output "FeatureDisabled=$id"
    }
}

$after = Get-StateMap -Path $mountDir -Kind $kind
$digests = @{}
foreach ($id in ($ids | Select-Object -Unique)) {
    $state = $after[$id]
    if ($kind -eq 'capability') {
        if (-not $state -or $state -ieq 'NotPresent' -or $state -ieq 'Absent' -or $state -ieq 'Not Present') {
            $digests["removed.capability.$id"] = 'Absent'
        }
        else { throw "Capability '$id' still present after remove (state=$state)" }
    }
    else {
        if (-not $state -or $state -ieq 'Disabled' -or $state -ieq 'DisabledWithPayloadRemoved') {
            $digests["disabled.feature.$id"] = 'Disabled'
        }
        else { throw "Optional feature '$id' not Disabled after disable (state=$state)" }
    }
}
Save-DigestMap $digests

Write-Output ("MutateOffline {0} ok count={1}" -f $kind, $ids.Count)
exit 0
