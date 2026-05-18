#Requires -Version 7.3

<#
.SYNOPSIS
    Literal-safe filesystem helpers for WinMint UI PowerShell code.
.NOTES
    Avoids PowerShell cmdlet foot-guns (e.g. Split-Path -LiteralPath cannot combine with -Parent).
    Prefer these from Services/ViewModels instead of ad hoc IO patterns.
#>

function Get-WinMintPathParentDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return [string]::Empty }
    return [string][System.IO.Path]::GetDirectoryName($Path)
}

function New-WinMintDirectoryLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )
    if ([string]::IsNullOrWhiteSpace($LiteralPath)) { return }
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        $null = New-Item -ItemType Directory -LiteralPath $LiteralPath -Force -ErrorAction Stop
    }
}

function Set-WinMintUtf8NoBomTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )
    $parent = Get-WinMintPathParentDirectory -Path $LiteralPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-WinMintDirectoryLiteral -LiteralPath $parent
    }
    [System.IO.File]::WriteAllText($LiteralPath, $Content, [System.Text.UTF8Encoding]::new($false))
}
