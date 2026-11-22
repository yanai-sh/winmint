#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Read-RepoText([string] $RelativePath) {
    return Get-Content -LiteralPath (Join-Path $repo $RelativePath) -Raw -Encoding utf8
}

$letters = 'C D E F G H I J K L M N O P Q R S T U V W Y Z'
$assign = 'if not defined INSTALL if exist %%d:\usb-media.json if exist %%d:\sources\install.wim call :winmint_accept_install %%d'

foreach ($relative in @('payload/winpe/LaunchApply.cmd')) {
    $text = Read-RepoText $relative
    $lines = @($text -split '\r?\n')

    $walk = @($lines | Where-Object { $_ -match 'for %%d in \(' })
    if ($walk.Count -ne 2) {
        throw "$relative must walk letters twice: once to read markers, once to accept the boot disk"
    }
    $seenAssign = 'if not defined SEEN if exist %%d:\usb-media.json if exist %%d:\sources\install.wim set "SEEN=%%d"'
    $seen = @($lines | Where-Object { $_.Trim() -eq $seenAssign })
    if ($seen.Count -ne 1) {
        throw "$relative must record a payload letter without setting INSTALL"
    }
    foreach ($one in $walk) {
        if ($one -notmatch [regex]::Escape("for %%d in ($letters)")) {
            throw "$relative must walk $letters in that order"
        }
        $listed = [regex]::Match($one, 'for %%d in \((?<letters>[^)]*)\)').Groups['letters'].Value
        foreach ($letter in ($listed -split '\s+' | Where-Object { $_ })) {
            if ($letter -ceq 'X') {
                throw "$relative must not include X in the letter list"
            }
        }
        if ($listed -match '(?i)(^|\s)X(\s|$)') {
            throw "$relative must not include X in the letter list"
        }
    }

    $sets = @($lines | Where-Object { $_ -match 'call :winmint_accept_install %%d' })
    if ($sets.Count -ne 1) {
        throw "$relative must accept an install volume from the drive walk once"
    }
    $setLine = $sets[0].Trim()
    if ($setLine -ne $assign) {
        throw "$relative must accept a letter only when usb-media.json and sources\install.wim both exist, and must not overwrite INSTALL: $setLine"
    }
    if ($text -match 'set INSTALL=%%d') {
        throw "$relative must not set INSTALL from the drive walk; :winmint_accept_install checks the boot disk first"
    }
    $existChecks = [regex]::Matches($setLine, 'if exist ')
    if ($existChecks.Count -ne 2 -or $setLine.IndexOf('if exist %%d:\usb-media.json', [StringComparison]::Ordinal) -lt 0 -or $setLine.IndexOf('if exist %%d:\sources\install.wim', [StringComparison]::Ordinal) -lt 0) {
        throw "$relative must put both if exist checks on the set INSTALL line"
    }
    $wimAt = $setLine.IndexOf('if exist %%d:\sources\install.wim', [StringComparison]::Ordinal)
    $setAt = $setLine.IndexOf('call :winmint_accept_install %%d', [StringComparison]::Ordinal)
    if ($wimAt -lt 0 -or $setAt -lt $wimAt) {
        throw "$relative must not accept a letter from install.wim alone"
    }
    if ($setLine -notmatch 'if not defined INSTALL') {
        throw "$relative must guard set INSTALL with if not defined INSTALL"
    }
    if ($setLine -match 'if exist %%d:\\sources\\install\.wim set INSTALL=%%d' -and $setLine -notmatch 'usb-media\.json') {
        throw "$relative must not accept install.wim without usb-media.json"
    }
}

Write-Output 'Test-InstallVolume ok'
exit 0
