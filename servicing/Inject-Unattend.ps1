#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$unattendPath = $Parameters['unattendPath']
$mountDir = $Parameters['mountDir']
$mediaDir = $Parameters['mediaDir']
if ([string]::IsNullOrWhiteSpace($unattendPath)) { throw 'unattendPath required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }

$panther = Join-Path $mountDir 'Windows\Panther'
New-Item -ItemType Directory -Force -Path $panther | Out-Null
Copy-Item -LiteralPath $unattendPath -Destination (Join-Path $panther 'unattend.xml') -Force

# WinPE reads Autounattend.xml from the install ISO root (SPLASH) — Panther alone is too late.
$auto = Join-Path $mediaDir 'Autounattend.xml'
Copy-Item -LiteralPath $unattendPath -Destination $auto -Force
Write-Output "Autounattend.xml → $auto"

# 25H2 ConX Setup ignores much of Autounattend — force legacy setup.exe (SPLASH / community).
$bootWim = Join-Path $mediaDir 'sources\boot.wim'
$bootMarker = Join-Path $mediaDir 'sources\.winmint-boot-legacy'
if (-not (Test-Path -LiteralPath $bootWim)) {
    throw "boot.wim missing under media (expected $bootWim)"
}
if (-not (Test-Path -LiteralPath $bootMarker)) {
    $bootItem = Get-Item -LiteralPath $bootWim
    if ($bootItem.IsReadOnly) { $bootItem.IsReadOnly = $false }
    # Sibling of install mount under %ProgramData%\WinMint\Servicing (or legacy workdir parent).
    $bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
    if (Test-Path -LiteralPath $bootMount) {
        # Best-effort discard leftover
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
        Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $bootMount | Out-Null
    $info = & dism.exe /English /Get-WimInfo /WimFile:$bootWim 2>&1 | Out-String
    $indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
    if ($indexes.Count -eq 0) { throw 'boot.wim has no indexes' }
    $winpeshl = @"
[LaunchApps]
%SYSTEMDRIVE%\sources\setup.exe, /legacy
"@
    foreach ($index in $indexes) {
        Write-Output "Patch boot.wim index $index (LabConfig + winpeshl legacy)"
        & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:$index /MountDir:$bootMount
        if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:$index failed: $LASTEXITCODE" }
        try {
            Set-Content -LiteralPath (Join-Path $bootMount 'Windows\System32\winpeshl.ini') -Value $winpeshl -Encoding ascii
            $sysHive = Join-Path $bootMount 'Windows\System32\config\SYSTEM'
            & reg.exe load 'HKLM\WinMintBoot' $sysHive
            if ($LASTEXITCODE -ne 0) { throw "reg load boot SYSTEM failed: $LASTEXITCODE" }
            try {
                foreach ($name in @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck')) {
                    & reg.exe add 'HKLM\WinMintBoot\Setup\LabConfig' /v $name /t REG_DWORD /d 1 /f | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "reg add LabConfig\$name failed" }
                }
            }
            finally {
                [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                & reg.exe unload 'HKLM\WinMintBoot'
                if ($LASTEXITCODE -ne 0) { throw "reg unload boot SYSTEM failed: $LASTEXITCODE" }
            }
        }
        finally {
            & dism.exe /English /Unmount-Image /MountDir:$bootMount /Commit
            if ($LASTEXITCODE -ne 0) { throw "Unmount boot.wim:$index failed: $LASTEXITCODE" }
        }
    }
    Set-Content -LiteralPath $bootMarker -Value 'legacy+labconfig' -Encoding utf8
    Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "InjectUnattend ok"
exit 0
