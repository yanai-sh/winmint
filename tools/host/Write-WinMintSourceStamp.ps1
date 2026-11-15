#requires -Version 7.6
<#
.SYNOPSIS
  Write a source-tree SHA-256 beside a published exe. Same bytes as ImageServicing.ComputeSourceTreeDigest.
#>
param(
    [string] $Exe,
    [string[]] $SourceRoots
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WinMintSourceTreeDigest {
    param([Parameter(Mandatory)] [string[]] $Roots)

    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $project = Split-Path -Leaf $root
        foreach ($file in [IO.Directory]::EnumerateFiles($root, '*.cs', [IO.SearchOption]::AllDirectories)) {
            if ($file.Contains([IO.Path]::DirectorySeparatorChar + 'obj' + [IO.Path]::DirectorySeparatorChar) -or
                $file.Contains([IO.Path]::DirectorySeparatorChar + 'bin' + [IO.Path]::DirectorySeparatorChar)) {
                continue
            }
            $relative = [IO.Path]::GetRelativePath($root, $file).Replace('\', '/')
            $files.Add([pscustomobject]@{ Path = "$project/$relative"; Full = $file })
        }
    }

    $ordered = $files.ToArray()
    [Array]::Sort($ordered, [System.Comparison[object]]{
            param($left, $right)
            [string]::CompareOrdinal([string]$left.Path, [string]$right.Path)
        })

    $sha = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $nl = [byte[]](10)
        foreach ($file in $ordered) {
            $sha.AppendData([Text.Encoding]::UTF8.GetBytes([string]$file.Path))
            $sha.AppendData($nl)
            $sha.AppendData([IO.File]::ReadAllBytes([string]$file.Full))
            $sha.AppendData($nl)
        }
        return [Convert]::ToHexString($sha.GetHashAndReset()).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-WinMintSourceStamp {
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $SourceRoots
    )

    $digest = Get-WinMintSourceTreeDigest -Roots $SourceRoots
    [IO.File]::WriteAllText("$Exe.sha256", $digest)
}

function Test-WinMintPublishedStampCurrent {
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string[]] $SourceRoots
    )

    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }
    $present = @($SourceRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    if ($present.Count -eq 0) { return $true }
    $stamp = "$Exe.sha256"
    if (-not (Test-Path -LiteralPath $stamp -PathType Leaf)) { return $false }
    $expected = (Get-Content -LiteralPath $stamp -Raw).Trim()
    $actual = Get-WinMintSourceTreeDigest -Roots $present
    return $expected -ceq $actual
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($Exe) -or $null -eq $SourceRoots -or $SourceRoots.Count -eq 0) {
        throw 'Write-WinMintSourceStamp -Exe <path> -SourceRoots <dir>[,<dir>]'
    }
    Write-WinMintSourceStamp -Exe $Exe -SourceRoots $SourceRoots
}
