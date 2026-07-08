#Requires -Version 7.6
<#
.SYNOPSIS
  One-shot migration from BuildProfile schema v3 to v4.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'src\runtime\image\WinMint.ps1')

if (@($Path).Count -eq 0) {
    $Path = @(
        (Join-Path $repoRoot 'config\build-profiles'),
        (Join-Path $repoRoot 'tests\profiles')
    )
}

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($item in $Path) {
    if (Test-Path -LiteralPath $item -PathType Leaf) {
        $files.Add((Get-Item -LiteralPath $item))
        continue
    }
    if (Test-Path -LiteralPath $item -PathType Container) {
        Get-ChildItem -LiteralPath $item -Filter '*.json' -File | ForEach-Object { $files.Add($_) }
    }
}
$files = @($files | Sort-Object FullName -Unique)
if ($files.Count -eq 0) { throw 'No profile JSON files found to migrate.' }

foreach ($file in $files) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ([int]$raw.schemaVersion -eq 4) {
        Write-Host "Skip (already v4): $($file.FullName)"
        continue
    }
    if ([int]$raw.schemaVersion -ne 3) {
        throw "Unsupported schemaVersion in $($file.FullName): $($raw.schemaVersion)"
    }

    $result = Convert-WinMintBuildProfileV3ToV4 -BuildProfile $raw -PassThru
    foreach ($warning in @($result.Warnings)) {
        Write-Warning "$($file.Name): $warning"
    }
    $json = ($result.Profile | ConvertTo-Json -Depth 16) + [Environment]::NewLine
    if ($PSCmdlet.ShouldProcess($file.FullName, 'migrate BuildProfile v3 to v4')) {
        $backup = "$($file.FullName).v3.bak"
        Copy-Item -LiteralPath $file.FullName -Destination $backup -Force
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($file.FullName, $json, $utf8NoBom)
        Write-Host "Migrated: $($file.FullName)"
    }
}
