#requires -Version 7.6
param(
    [hashtable] $Parameters
)

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

function Get-WinMintOscdimgBootData {
    param([Parameter(Mandatory)] [string] $MediaDir)
    $etfsboot = Join-Path $MediaDir 'boot\etfsboot.com'
    $efisys = Join-Path $MediaDir 'efi\microsoft\boot\efisys_noprompt.bin'
    if (-not (Test-Path -LiteralPath $efisys)) {
        $efisys = Join-Path $MediaDir 'efi\microsoft\boot\efisys.bin'
    }
    if (-not (Test-Path -LiteralPath $efisys)) { throw "efisys*.bin missing under $MediaDir\efi\microsoft\boot" }
    if (Test-Path -LiteralPath $etfsboot) {
        return "2#p0,e,b$etfsboot#pEF,e,b$efisys"
    }
    return "1#pEF,e,b$efisys"
}

if ($MyInvocation.InvocationName -ne '.') {
    $outputIso = $Parameters['outputIso']
    $mediaDir = $Parameters['mediaDir']
    if ([string]::IsNullOrWhiteSpace($outputIso)) { throw 'outputIso required' }
    if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
    if (-not (Test-Path -LiteralPath $mediaDir)) { throw "mediaDir missing: $mediaDir" }

    $oscdimg = Find-Oscdimg
    if (-not $oscdimg) { throw 'oscdimg.exe not found (install ADK Deployment Tools)' }

    $bootdata = Get-WinMintOscdimgBootData -MediaDir $mediaDir

    $outDir = Split-Path -Parent $outputIso
    if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    if (Test-Path -LiteralPath $outputIso) { Remove-Item -LiteralPath $outputIso -Force }

    Write-Output "oscdimg → $outputIso"
    & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootdata" $mediaDir $outputIso
    if ($LASTEXITCODE -ne 0) { throw "oscdimg failed: $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $outputIso)) { throw "oscdimg produced no file: $outputIso" }

    Write-Output "BuildIso ok outputIso=$outputIso"
    exit 0
}
