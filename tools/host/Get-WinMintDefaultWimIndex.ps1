#requires -Version 7.6
<#
.SYNOPSIS
  Host EditionID → default install.wim index (Home=1, Pro family=3).
.NOTES
  Mirrors WinMint.Wizard.BuildMachineEdition — Primary Gate / Host Apply only.
  Cli / Smoke keep omitting --wim-index so HostCompile defaults to Pro (3).
#>
function Get-WinMintDefaultWimIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string] $EditionId = ''
    )

    if ([string]::IsNullOrWhiteSpace($EditionId)) {
        try {
            $EditionId = [string](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
        }
        catch {
            $EditionId = ''
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($EditionId) -and (
            $EditionId.StartsWith('Professional', [StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($EditionId, 'Pro', [StringComparison]::OrdinalIgnoreCase))) {
        return 3
    }

    return 1
}
