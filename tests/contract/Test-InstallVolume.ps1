#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Read-RepoText([string] $RelativePath) {
    return Get-Content -LiteralPath (Join-Path $repo $RelativePath) -Raw -Encoding utf8
}

$letters = 'C D E F G H I J K L M N O P Q R S T U V W Y Z'

foreach ($relative in @('payload/winpe/LaunchApply.cmd')) {
    $text = Read-RepoText $relative
    $lines = @($text -split '\r?\n')

    $walk = @($lines | Where-Object { $_ -match 'for %%d in \(' })
    if ($walk.Count -ne 1) {
        throw "$relative must walk letters once to read markers, then confirm that letter"
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

    if (@($lines | Where-Object { $_ -match 'call :winmint_accept_install %%d' }).Count -ne 0) {
        throw "$relative must not accept a different letter after the install file was read"
    }
    $sets = @($lines | Where-Object { $_.Trim() -eq 'call :winmint_accept_install %INSTALL%' })
    if ($sets.Count -ne 1) {
        throw "$relative must confirm the letter that held the install file"
    }
    if (@($lines | Where-Object { $_.Trim() -eq 'for /L %%i in (1,1,10) do if not defined PAYLOADDISK call :winmint_find_install' }).Count -ne 1) {
        throw "$relative must retry boot-disk confirmation ten times"
    }
    if ($text -match 'set INSTALL=%%d') {
        throw "$relative must not set INSTALL from the drive walk; :winmint_accept_install checks the boot disk first"
    }
}

Write-Output 'Test-InstallVolume ok'
exit 0
