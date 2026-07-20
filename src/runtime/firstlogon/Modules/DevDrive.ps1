#Requires -Version 7.6

function Get-WinMintDevDriveModuleConfig {
    param([Parameter(Mandatory)][object]$AgentProfile)

    if (-not $AgentProfile.modules) { return $null }
    if ($AgentProfile.modules -is [System.Collections.IDictionary]) {
        if (-not $AgentProfile.modules.Contains('devDrive')) { return $null }
        return $AgentProfile.modules['devDrive']
    }
    if (-not $AgentProfile.modules.PSObject.Properties['devDrive']) { return $null }
    return $AgentProfile.modules.devDrive
}

function Get-WinMintDevDriveLabeledVolume {
    $labels = @('DevDrive', 'WinMint-DevDrive')
    foreach ($vol in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' })) {
        if ($labels -contains [string]$vol.FileSystemLabel) { return $vol }
    }
    return $null
}

function Test-WinMintDevDriveTrusted {
    param([Parameter(Mandatory)][char]$DriveLetter)

    $letter = ([string]$DriveLetter).TrimEnd(':').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($letter)) { return $false }
    try {
        $query = & fsutil.exe devdrv query "${letter}:" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return $false }
        # Trusted Dev Drive volumes report as designated / trusted in fsutil output.
        return ($query -match '(?i)(is a Dev Drive|Dev Drive\s*:\s*Yes|Trusted)')
    }
    catch {
        return $false
    }
}

function Format-WinMintDevDriveVolume {
    param([Parameter(Mandatory)][char]$DriveLetter)

    $letter = ([string]$DriveLetter).TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($letter)) { throw 'Drive letter required to format Dev Drive.' }
    # Format-Volume -DevDrive creates ReFS + Dev Drive trust (Microsoft Learn).
    Format-Volume -DriveLetter $letter -FileSystem ReFS -DevDrive -NewFileSystemLabel 'DevDrive' -Confirm:$false -ErrorAction Stop | Out-Null
}

function Enable-WinMintPartitionDevDrive {
    # Partition mode: Setup diskpart already created an empty ReFS volume labeled DevDrive.
    # FirstLogon only assigns a letter (if needed) and applies Dev Drive trust.
    $vol = Get-WinMintDevDriveLabeledVolume
    if (-not $vol) {
        throw 'Partition Dev Drive volume (label DevDrive) was not found. Setup diskpart should have created it.'
    }

    $part = Get-Partition -Volume $vol -ErrorAction Stop | Select-Object -First 1
    if (-not $part) { throw 'DevDrive volume has no partition to assign a letter.' }
    if (-not $part.DriveLetter -or $part.DriveLetter -eq ([char]0)) {
        Add-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AssignDriveLetter -ErrorAction Stop
        $part = Get-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -ErrorAction Stop
    }
    $letter = [char]$part.DriveLetter
    if (-not $letter -or $letter -eq ([char]0)) {
        throw 'Failed to assign a drive letter to the DevDrive partition.'
    }

    if (Test-WinMintDevDriveTrusted -DriveLetter $letter) {
        return [string]$letter
    }

    Format-WinMintDevDriveVolume -DriveLetter $letter
    return [string]$letter
}

function New-WinMintDevDriveVhdDynamic {
    param([Parameter(Mandatory)][int]$SizeGb)

    $root = Join-Path $env:SystemDrive 'DevDrives'
    $null = New-Item -ItemType Directory -Path $root -Force
    $vhdPath = Join-Path $root 'WinMint.vhdx'
    if (Test-Path -LiteralPath $vhdPath) {
        throw "Dev Drive VHDX already exists at $vhdPath. Remove it before recreating."
    }

    $maxMb = [int]($SizeGb * 1024)
    $dp = @"
create vdisk file="$vhdPath" maximum=$maxMb type=expandable
select vdisk file="$vhdPath"
attach vdisk
create partition primary
assign
"@
    $path = Join-Path $env:TEMP ("winmint-devdrive-{0}.txt" -f [guid]::NewGuid().ToString('n'))
    $unix = ($dp -replace "`r`n", "`n" -replace "`r", "`n").Trim() + "`n"
    Set-Content -LiteralPath $path -Value $unix -Encoding ascii -NoNewline
    try {
        $output = & diskpart.exe /s $path 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "diskpart failed ($LASTEXITCODE): $output"
        }
    }
    finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    $disk = Get-Disk | Where-Object { $_.Location -like "*$([IO.Path]::GetFileName($vhdPath))*" -or $_.FriendlyName -match 'VHD' } |
        Sort-Object Number -Descending |
        Select-Object -First 1
    $part = $null
    if ($disk) {
        $part = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter } |
            Select-Object -First 1
    }
    if (-not $part) {
        $part = Get-Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'C' -and $_.Type -eq 'Basic' } |
            Sort-Object Size -Descending |
            Select-Object -First 1
    }
    if (-not $part -or -not $part.DriveLetter) {
        throw 'Dev Drive VHDX was attached but no drive letter was assigned.'
    }
    Format-WinMintDevDriveVolume -DriveLetter ([char]$part.DriveLetter)
    return [string]$part.DriveLetter
}

function Invoke-WinMintAgentDevDriveBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$State
    $cfg = Get-WinMintDevDriveModuleConfig -AgentProfile $AgentProfile
    if (-not $cfg) {
        return [pscustomobject]@{
            Id      = 'devDrive'
            Status  = 'skipped'
            Message = 'Dev Drive module is not present in the agent profile.'
        }
    }

    $enabled = $false
    $mode = 'Off'
    $sizeGb = 128
    if ($cfg -is [System.Collections.IDictionary]) {
        if ($cfg.Contains('enabled')) { $enabled = [bool]$cfg['enabled'] }
        if ($cfg.Contains('mode')) { $mode = [string]$cfg['mode'] }
        if ($cfg.Contains('sizeGb')) { $sizeGb = [int]$cfg['sizeGb'] }
    }
    else {
        if ($cfg.PSObject.Properties['enabled']) { $enabled = [bool]$cfg.enabled }
        if ($cfg.PSObject.Properties['mode']) { $mode = [string]$cfg.mode }
        if ($cfg.PSObject.Properties['sizeGb']) { $sizeGb = [int]$cfg.sizeGb }
    }

    if (-not $enabled -or $mode -eq 'Off') {
        return [pscustomobject]@{
            Id      = 'devDrive'
            Status  = 'skipped'
            Message = 'Dev Drive is Off.'
        }
    }
    if ($sizeGb -notin @(64, 128, 256)) {
        return [pscustomobject]@{
            Id      = 'devDrive'
            Status  = 'failed'
            Message = "Unsupported Dev Drive sizeGb=$sizeGb (expected 64, 128, or 256)."
        }
    }

    try {
        Write-AgentUserNotice -Level Info -Message "Preparing Dev Drive ($mode, ${sizeGb} GB)."
        $letter = switch ($mode) {
            'Partition' {
                # Volume was created at Setup; apply trust only.
                Enable-WinMintPartitionDevDrive
            }
            'VhdDynamic' {
                $vhdPath = Join-Path (Join-Path $env:SystemDrive 'DevDrives') 'WinMint.vhdx'
                if (Test-Path -LiteralPath $vhdPath) {
                    $existing = Get-WinMintDevDriveLabeledVolume
                    if ($existing -and $existing.DriveLetter -and $existing.DriveLetter -ne ([char]0) -and
                        (Test-WinMintDevDriveTrusted -DriveLetter ([char]$existing.DriveLetter))) {
                        return [pscustomobject]@{
                            Id      = 'devDrive'
                            Status  = 'ok'
                            Message = "Dev Drive VHDX already present and trusted on $([char]$existing.DriveLetter):."
                        }
                    }
                    throw "Dev Drive VHDX already exists at $vhdPath but is not a trusted Dev Drive. Remove or fix it before retrying."
                }
                New-WinMintDevDriveVhdDynamic -SizeGb $sizeGb
            }
            default { throw "Unsupported Dev Drive mode: $mode" }
        }
        return [pscustomobject]@{
            Id      = 'devDrive'
            Status  = 'ok'
            Message = "Dev Drive ready on ${letter}: (mode=$mode sizeGb=$sizeGb)."
        }
    }
    catch {
        Write-AgentLog "Dev Drive failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            Id      = 'devDrive'
            Status  = 'failed'
            Message = $_.Exception.Message
        }
    }
}
