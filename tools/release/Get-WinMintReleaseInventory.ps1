#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $StageRoot,
    [Parameter(Mandatory)] [string] $Tag,
    [ValidateSet('Unsigned', 'Signed')] [string] $Phase = 'Unsigned',
    [string] $OutFile = '',
    [switch] $AllowPowerShellSigning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Get-WinMintReleaseVersion.ps1')

if (-not [System.IO.Path]::IsPathRooted($StageRoot)) {
    $StageRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')) $StageRoot
}
$stageFull = [IO.Path]::GetFullPath($StageRoot)
if (-not (Test-Path -LiteralPath $stageFull -PathType Container)) {
    throw "StageRoot missing: $stageFull"
}

$commit = ('0' * 40)
try { $commit = (git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD).Trim().ToLowerInvariant() } catch { }
$version = Convert-WinMintReleaseTag -Tag $Tag -Commit $commit

$winmintPeAllow = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rel in @(
        'bin\cli\WinMint.Cli.exe',
        'bin\cli\WinMint.Contracts.dll',
        'bin\cli\WinMint.Orchestrator.dll',
        'bin\wizard\WinMint.Wizard.exe',
        'bin\wizard\WinMint.Contracts.dll',
        'bin\wizard\WinMint.Orchestrator.dll',
        'artifacts\provisioning\WinMint.Provisioning.exe',
        'artifacts\provisioning\Supervisor.exe',
        'artifacts\winpe-apply\WinMintApply.exe'
    )) { [void]$winmintPeAllow.Add($rel) }

$generatedAfterSigning = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rel in @('unsigned-manifest.json', 'release-manifest.json')) { [void]$generatedAfterSigning.Add($rel) }

function Get-Rel([string] $Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $stageFull.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "file escapes stage root: $Path"
    }
    return $full.Substring($prefix.Length)
}

$files = Get-ChildItem -LiteralPath $stageFull -Recurse -File -Force
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $rel = Get-Rel $file.FullName
    $ext = $file.Extension
    $class = $null
    $relNorm = $rel.Replace('/', '\')
    $underHostPublish = $relNorm.StartsWith('bin\cli\', [StringComparison]::OrdinalIgnoreCase) -or
        $relNorm.StartsWith('bin\wizard\', [StringComparison]::OrdinalIgnoreCase) -or
        $relNorm.StartsWith('artifacts\provisioning\', [StringComparison]::OrdinalIgnoreCase) -or
        $relNorm.StartsWith('artifacts\winpe-apply\', [StringComparison]::OrdinalIgnoreCase)
    $underScripts = $relNorm.StartsWith('servicing\', [StringComparison]::OrdinalIgnoreCase) -or
        $relNorm.StartsWith('tools\', [StringComparison]::OrdinalIgnoreCase) -or
        $relNorm.StartsWith('payload\', [StringComparison]::OrdinalIgnoreCase)

    if ($generatedAfterSigning.Contains($rel) -or $generatedAfterSigning.Contains($relNorm)) {
        $class = 'generated-after-signing'
    }
    elseif ($ext -in @('.exe', '.dll')) {
        if ($winmintPeAllow.Contains($relNorm) -or $winmintPeAllow.Contains($rel)) {
            $class = 'winmint-pe'
        }
        elseif ($file.Name -like 'WinMint.*') {
            throw "WinMint PE not on allowlist: $rel"
        }
        elseif ($underHostPublish) {
            $class = 'upstream-pe'
        }
        else {
            throw "unknown executable: $rel"
        }
    }
    elseif ($ext -eq '.ps1') {
        if (-not $underScripts) { throw "unknown script: $rel" }
        $class = 'winmint-powershell'
    }
    else {
        $class = 'hash-only'
    }

    $signingCandidate = $false
    if ($class -eq 'winmint-pe') { $signingCandidate = $true }
    if ($class -eq 'winmint-powershell' -and $AllowPowerShellSigning) { $signingCandidate = $true }
    if ($class -eq 'upstream-pe' -and $signingCandidate) {
        throw "upstream path marked signing candidate: $rel"
    }

    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $entries.Add([ordered]@{
            path              = $rel.Replace('\', '/')
            class             = $class
            signingCandidate  = $signingCandidate
            sha256            = $hash
            length            = $file.Length
        })
}

$doc = [ordered]@{
    schemaVersion = 'winmint.release.inventory/v1'
    phase         = $Phase.ToLowerInvariant()
    tag           = $Tag
    version       = $version.Version
    commit        = $commit
    origin        = 'local'
    files         = @($entries)
}

if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $parent = Split-Path -Parent $OutFile
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    ($doc | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $OutFile -Encoding utf8
}

return $doc
