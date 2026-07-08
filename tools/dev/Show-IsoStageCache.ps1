#Requires -Version 7.6
$root = Join-Path $env:LOCALAPPDATA 'WinMint\cache\iso-stage'
Write-Host "cache root: $root exists=$(Test-Path $root)"
if (Test-Path $root) {
    Get-ChildItem $root -Directory | ForEach-Object {
        $dir = $_.FullName
        $efi1 = Join-Path $dir 'efi\microsoft\boot\efisys.bin'
        $efi2 = Join-Path $dir 'efi\microsoft\boot\efisys_noprompt.bin'
        Write-Host "$($_.Name) efisys=$(Test-Path $efi1) noprompt=$(Test-Path $efi2) bootwim=$(Test-Path (Join-Path $dir 'sources\boot.wim')) installwim=$(Test-Path (Join-Path $dir 'sources\install.wim'))"
    }
}
