#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline provisioned AppX remove — param-only; no Profile branching.
# Policy (KEEPFLAG): listed id with no matching provisioned package ⇒ fail closed.
$mountDir = $Parameters['mountDir']
$packageFamilyNames = $Parameters['packageFamilyNames']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($packageFamilyNames)) { throw 'packageFamilyNames required' }

$ids = @(
    $packageFamilyNames.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ids.Count -eq 0) { throw 'packageFamilyNames empty after split' }

$workDir = Split-Path -Parent $mountDir
$logDir = Join-Path $workDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$inventoryBefore = Join-Path $logDir 'provisioned-appx.before.txt'
$inventoryAfter = Join-Path $logDir 'provisioned-appx.after.txt'
$dismLog = Join-Path $logDir 'remove-provisioned-appx.dism.log'
$digestPath = Join-Path $logDir 'remove-provisioned-appx.digests.json'

Import-Module Dism -ErrorAction Stop

function Get-ProvisionedInventory {
    param([string] $Path)
    return @(Get-AppxProvisionedPackage -Path $Path -ErrorAction Stop)
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
    # Fallback: PackageName is DisplayName_Version_Arch_Resource_PublisherId — take first + last segments.
    $parts = ([string]$Package.PackageName) -split '_'
    if ($parts.Count -ge 2) {
        return "$($parts[0])_$($parts[-1])"
    }
    return [string]$Package.PackageName
}

$before = Get-ProvisionedInventory -Path $mountDir
$before |
    ForEach-Object { "$($_.DisplayName)`t$($_.PackageName)`t$($_.PublisherId)" } |
    Set-Content -LiteralPath $inventoryBefore -Encoding utf8

$removed = [System.Collections.Generic.List[object]]::new()
foreach ($id in $ids) {
    $matchedPkgs = @($before | Where-Object { Test-PackageMatchesCatalogId -Package $_ -CatalogId $id })
    if ($matchedPkgs.Count -eq 0) {
        throw "Absent provisioned AppX for catalog id '$id' (fail-closed; Profile asserted remove)."
    }
    foreach ($pkg in $matchedPkgs) {
        $packageName = [string]$pkg.PackageName
        Write-Output "Remove-AppxProvisionedPackage PackageName=$packageName catalogId=$id"
        Remove-AppxProvisionedPackage -Path $mountDir -PackageName $packageName -LogPath $dismLog -ErrorAction Stop
        $removed.Add([pscustomobject]@{
                CatalogId         = $id
                PackageName       = $packageName
                PackageFamilyName = (Get-PackageFamilyName -Package $pkg)
            })
    }
}

$after = Get-ProvisionedInventory -Path $mountDir
$after |
    ForEach-Object { "$($_.DisplayName)`t$($_.PackageName)`t$($_.PublisherId)" } |
    Set-Content -LiteralPath $inventoryAfter -Encoding utf8

foreach ($row in $removed) {
    $still = @($after | Where-Object { [string]$_.PackageName -ieq $row.PackageName })
    if ($still.Count -gt 0) {
        throw "Package still provisioned after remove: $($row.PackageName)"
    }
}

# Deprovisioned stamps — survive feature-update reintroduction (KEEPFLAG / rehydrate research).
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

$digests = [ordered]@{}
foreach ($id in ($ids | Select-Object -Unique)) {
    $digests["removed.appx.$id"] = 'absent'
}
$digests | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8

Write-Output "RemoveProvisionedAppx ok count=$($removed.Count)"
exit 0
