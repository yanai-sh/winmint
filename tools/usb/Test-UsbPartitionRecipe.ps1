#requires -Version 7.6
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'USB partition recipe proof requires Windows' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'USB partition recipe proof requires an elevated PowerShell 7.6 process'
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
# 512MB is large enough for Format-Volume -FileSystem FAT32. Production receipts floor the boot partition at 2GB.
$bootBytes = [long] 512MB
$imageBytes = $bootBytes + [long] 128MB + [long] 64MB
$espType = [guid] 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-usb-partition-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $tmp 'work'
$mediaDir = Join-Path $work 'media'
$image = Join-Path $tmp 'recipe.vhdx'
$attached = $false

function Invoke-RecipeDiskpart {
    param([Parameter(Mandatory)] [string[]] $Lines)
    $scriptPath = Join-Path $tmp ('diskpart-' + [guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllLines($scriptPath, $Lines, [Text.Encoding]::ASCII)
    try {
        $output = & "$env:SystemRoot\System32\diskpart.exe" /s $scriptPath
        $exit = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
    }
    $text = $output -join "`n"
    if ($exit -ne 0 -or $text -match 'DiskPart has encountered an error') {
        throw "diskpart failed (${exit}): $text"
    }
}

function Resolve-RecipeDiskNumber {
    param([Parameter(Mandatory)] [string] $ImagePath)
    $imageFull = [IO.Path]::GetFullPath($ImagePath)
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    do {
        foreach ($disk in @(Get-Disk -ErrorAction Stop)) {
            $location = [string] $disk.Location
            if ([string]::IsNullOrWhiteSpace($location)) { continue }
            if ($location.StartsWith('\\?\')) { $location = $location.Substring(4) }
            try {
                $locationFull = [IO.Path]::GetFullPath($location)
            }
            catch {
                continue
            }
            if ($locationFull.Equals($imageFull, [StringComparison]::OrdinalIgnoreCase)) {
                return [int] $disk.Number
            }
        }
        Start-Sleep -Milliseconds 250
    } while ($deadline.Elapsed.TotalSeconds -lt 15)
    throw 'Mounted recipe VHD has no disk number'
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $mediaDir 'efi\boot') | Out-Null
    $receiptPath = Join-Path $work 'usb-media.json'
    Set-Content -LiteralPath (Join-Path $mediaDir 'efi\boot\bootaa64.efi') -Value 'fixture' -Encoding ascii -NoNewline
    Set-Content -LiteralPath $receiptPath -Encoding utf8 -Value '{"schemaVersion":"winmint.usb-media/v1"}'
    $work = (Resolve-Path -LiteralPath $work).Path
    $mediaDir = Join-Path $work 'media'
    $receiptPath = Join-Path $work 'usb-media.json'
    $sourceFile = Join-Path $mediaDir 'efi\boot\bootaa64.efi'
    $image = Join-Path $tmp 'recipe.vhdx'
    . (Join-Path $repo 'servicing\Write-UsbMedia.ps1') -WorkDirectory $work -DiskNumber 0

    $receipt = [pscustomobject]@{
        Path = $receiptPath
        Sha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Document = [pscustomobject]@{
            layout = [pscustomobject]@{
                boot = [pscustomobject]@{
                    partitionBytes = $bootBytes
                }
            }
            files = @([pscustomobject]@{
                    path = 'efi/boot/bootaa64.efi'
                    destination = 'both'
                    length = [long] (Get-Item -LiteralPath $sourceFile).Length
                    sha256 = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()
                })
        }
    }

    $imageMb = [int] ($imageBytes / 1MB)
    Invoke-RecipeDiskpart @(
        "create vdisk file=`"$image`" maximum=$imageMb type=expandable",
        "select vdisk file=`"$image`"",
        'attach vdisk'
    )
    $attached = $true
    $diskNumber = Resolve-RecipeDiskNumber -ImagePath $image
    $recipeDisk = Get-Disk -Number $diskNumber -ErrorAction Stop
    if ($recipeDisk.IsBoot -or $recipeDisk.IsSystem) {
        throw "Refusing to initialize boot/system disk $diskNumber"
    }
    Set-Disk -Number $diskNumber -IsOffline $false -ErrorAction Stop
    Set-Disk -Number $diskNumber -IsReadOnly $false -ErrorAction Stop
    Write-WinMintUsbPartitionContent -DiskNumber $diskNumber -MediaDir $mediaDir -Receipt $receipt | Out-Null

    $diskAfter = Get-Disk -Number $diskNumber -ErrorAction Stop
    $esp = @(Get-Partition -DiskNumber $diskNumber -ErrorAction Stop | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string] $_.GptType) -and [guid] $_.GptType -eq $espType
        })
    if ([string] $diskAfter.PartitionStyle -cne 'GPT' -or $esp.Count -ne 1) {
        throw 'USB partition recipe did not leave a GPT disk with one EFI System Partition'
    }
}
finally {
    if ($attached) {
        try {
            Invoke-RecipeDiskpart @(
                "select vdisk file=`"$image`"",
                'detach vdisk'
            )
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'UsbPartitionRecipe ok'
exit 0
