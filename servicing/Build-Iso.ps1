#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$outputIso = $Parameters['outputIso']
$mediaDir = $Parameters['mediaDir']
if ([string]::IsNullOrWhiteSpace($outputIso)) { throw 'outputIso required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if (-not (Test-Path -LiteralPath $mediaDir)) { throw "mediaDir missing: $mediaDir" }

function Find-Oscdimg {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\arm64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\arm64\Oscdimg\oscdimg.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $onPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

$oscdimg = Find-Oscdimg
if (-not $oscdimg) { throw 'oscdimg.exe not found (install ADK Deployment Tools)' }

$etfsboot = Join-Path $mediaDir 'boot\etfsboot.com'
$efisys = Join-Path $mediaDir 'efi\microsoft\boot\efisys_noprompt.bin'
if (-not (Test-Path -LiteralPath $efisys)) {
    $efisys = Join-Path $mediaDir 'efi\microsoft\boot\efisys.bin'
}
if (-not (Test-Path -LiteralPath $efisys)) { throw "efisys*.bin missing under $mediaDir\efi\microsoft\boot" }

$outDir = Split-Path -Parent $outputIso
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $outputIso) { Remove-Item -LiteralPath $outputIso -Force }

# UEFI (+ BIOS bootdata when etfsboot present). ARM64 consumer ISOs are UEFI-primary.
if (Test-Path -LiteralPath $etfsboot) {
    $bootdata = "2#p0,e,b$etfsboot#pEF,e,b$efisys"
}
else {
    $bootdata = "1#pEF,e,b$efisys"
}

Write-Host "oscdimg → $outputIso"
& $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $mediaDir $outputIso
if ($LASTEXITCODE -ne 0) { throw "oscdimg failed: $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $outputIso)) { throw "oscdimg produced no file: $outputIso" }

Write-Host "BuildIso ok outputIso=$outputIso"
exit 0
