#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline provisioned AppX remove — param-only; no Profile branching.
# Policy (KEEPFLAG): Plan ⊆ catalog (typos fail at plan). Remove is idempotent: already-absent ⇒ ok + digest absent
# (reuse-media re-Apply after a prior remove). Uses dism.exe (not DISM AppX cmdlets) — Store pwsh
# hits "Class not registered" on those COM APIs.
$mountDir = $Parameters['mountDir']
$packageFamilyNames = $Parameters['packageFamilyNames']
$workDir = $Parameters['workDirectory']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($packageFamilyNames)) { throw 'packageFamilyNames required' }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }

$ids = @(
    $packageFamilyNames.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ids.Count -eq 0) { throw 'packageFamilyNames empty after split' }

$logDir = Join-Path $workDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$dismLog = Join-Path $logDir 'remove-provisioned-appx.dism.log'
$digestPath = Join-Path $logDir 'digests.json'

function Get-ProvisionedInventory {
    param([string] $Path)
    $text = & dism.exe /English /Image:$Path /Get-ProvisionedAppxPackages 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "dism Get-ProvisionedAppxPackages failed: $LASTEXITCODE`n$text"
    }
    $pkgs = [System.Collections.Generic.List[object]]::new()
    $cur = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^DisplayName\s*:\s*(.+)\s*$') {
            if ($null -ne $cur) { $pkgs.Add($cur) }
            $cur = [pscustomobject]@{
                DisplayName  = $Matches[1].Trim()
                PackageName  = ''
                PublisherId  = ''
            }
        }
        elseif ($null -ne $cur -and $line -match '^PackageName\s*:\s*(.+)\s*$') {
            $cur.PackageName = $Matches[1].Trim()
            $parts = $cur.PackageName -split '_'
            if ($parts.Count -ge 2) {
                $cur.PublisherId = $parts[-1]
            }
        }
    }
    if ($null -ne $cur) { $pkgs.Add($cur) }
    return @($pkgs)
}

function Test-PackageMatchesCatalogId {
    param($Package, [string] $CatalogId)
    if ($null -eq $Package -or [string]::IsNullOrWhiteSpace($CatalogId)) { return $false }
    $display = [string]$Package.DisplayName
    $name = [string]$Package.PackageName
    if ($display -and ($display -ieq $CatalogId)) { return $true }
    if ($name -and ($name.StartsWith($CatalogId + '_', [System.StringComparison]::OrdinalIgnoreCase))) { return $true }
    return $false
}

function Get-PackageFamilyName {
    param($Package)
    $display = [string]$Package.DisplayName
    $publisher = [string]$Package.PublisherId
    if (-not [string]::IsNullOrWhiteSpace($display) -and -not [string]::IsNullOrWhiteSpace($publisher)) {
        return "${display}_${publisher}"
    }
    $parts = ([string]$Package.PackageName) -split '_'
    if ($parts.Count -ge 2) {
        return "$($parts[0])_$($parts[-1])"
    }
    return [string]$Package.PackageName
}

$before = Get-ProvisionedInventory -Path $mountDir

$removed = [System.Collections.Generic.List[object]]::new()
foreach ($id in $ids) {
    $matchedPkgs = @($before | Where-Object { Test-PackageMatchesCatalogId -Package $_ -CatalogId $id })
    if ($matchedPkgs.Count -eq 0) {
        # Idempotent: prior Apply / reuse-media already stripped this id.
        Write-Output "Remove-ProvisionedAppx already absent catalogId=$id"
        continue
    }
    foreach ($pkg in $matchedPkgs) {
        $packageName = [string]$pkg.PackageName
        Write-Output "Remove-ProvisionedAppxPackage PackageName=$packageName catalogId=$id"
        & dism.exe /English /Image:$mountDir /Remove-ProvisionedAppxPackage /PackageName:$packageName /LogPath:$dismLog
        if ($LASTEXITCODE -ne 0) {
            throw "dism Remove-ProvisionedAppxPackage failed for $packageName : $LASTEXITCODE"
        }
        $removed.Add([pscustomobject]@{
                CatalogId         = $id
                PackageName       = $packageName
                PackageFamilyName = (Get-PackageFamilyName -Package $pkg)
            })
    }
}

$after = Get-ProvisionedInventory -Path $mountDir

foreach ($row in $removed) {
    $still = @($after | Where-Object { [string]$_.PackageName -ieq $row.PackageName })
    if ($still.Count -gt 0) {
        throw "Package still provisioned after remove: $($row.PackageName)"
    }
}

# Deprovisioned stamps — survive feature-update reintroduction (KEEPFLAG / rehydrate research).
if ($removed.Count -gt 0) {
    $hiveSoftware = Join-Path $mountDir 'Windows\System32\config\SOFTWARE'
    if (-not (Test-Path -LiteralPath $hiveSoftware)) { throw "SOFTWARE hive missing: $hiveSoftware" }
    $hiveKey = 'HKLM\WinMintAppx'
    $deprovRoot = 'HKLM\WinMintAppx\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
    Write-Output "REG LOAD $hiveKey (Deprovisioned stamps)"
    & reg.exe load $hiveKey $hiveSoftware
    if ($LASTEXITCODE -ne 0) { throw "reg load failed: $LASTEXITCODE" }
    try {
        foreach ($row in $removed) {
            $pfn = [string]$row.PackageFamilyName
            if ([string]::IsNullOrWhiteSpace($pfn)) { throw "PackageFamilyName empty for $($row.PackageName)" }
            $keyPath = "$deprovRoot\$pfn"
            & reg.exe add $keyPath /f
            if ($LASTEXITCODE -ne 0) { throw "reg add Deprovisioned\$pfn failed: $LASTEXITCODE" }
            # Readback assert — FU survival requires the mark to exist after write.
            & reg.exe query $keyPath > $null 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Deprovisioned stamp missing after write: $pfn" }
            Write-Output "Deprovisioned=$pfn"
        }
    }
    finally {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $hiveKey
        if ($LASTEXITCODE -ne 0) { throw "reg unload failed: $LASTEXITCODE" }
    }
}

$digests = @{}
foreach ($id in ($ids | Select-Object -Unique)) {
    $digests["removed.appx.$id"] = 'absent'
}
$map = [ordered]@{}
if (Test-Path -LiteralPath $digestPath) {
    foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
        $map[$p.Name] = [string]$p.Value
    }
}
foreach ($k in $digests.Keys) { $map[$k] = [string]$digests[$k] }
$map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8

Write-Output "RemoveProvisionedAppx ok count=$($removed.Count)"
exit 0
