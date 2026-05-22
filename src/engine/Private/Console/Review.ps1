#Requires -Version 7.3

function Get-RemovableUsbVolumeCandidate {
    <# <summary>Volumes Windows reports as Removable with an assigned drive letter (typical USB flash drives).</summary> #>
    return @(
        Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
            Sort-Object DriveLetter |
            ForEach-Object {
                $dl = $_.DriveLetter
                $freeGb = [math]::Round($_.SizeRemaining / 1GB, 1)
                $sizeGb = [math]::Round($_.Size / 1GB, 1)
                [pscustomobject]@{
                    DriveLetter = [string]$dl
                    SizeGb      = $sizeGb
                    FreeGb      = $freeGb
                    Label       = "[bold]${dl}:[/]  Removable USB  ·  [cyan]$sizeGb GB[/] total  ·  [green]$freeGb GB[/] free"
                }
            }
    )
}

function Show-BuildConfigurationSummaryAndConfirm {
    <# <summary>Rich summary, optional USB-after-build choice, then confirm to start the build or dry-run validation.</summary> #>
    param(
        [Parameter(Mandatory)][string]$SourceIsoPath,
        [Parameter(Mandatory)][string]$TargetArchitecture,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][bool]$AccountPasswordProvided,
        [Parameter(Mandatory)][bool]$AutoLogon,
        [Parameter(Mandatory)][string]$EditionName,
        [Parameter(Mandatory)][bool]$AutoWipeDisk,
        [Parameter(Mandatory)][bool]$MirrorHostRegional,
        [Parameter(Mandatory)][string]$TimeZoneId,
        [Parameter(Mandatory)][string]$InputLocale,
        [Parameter(Mandatory)][string]$UILanguage,
        [Parameter(Mandatory)][string]$UserLocale,
        [ValidateSet('Windows11Modern')][string]$CursorPackKind = 'Windows11Modern',
        [string]$DriverMode = 'None',
        [string]$DriverPath = '',
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
        [switch]$DryRun
    )

    Write-SectionHeader 'Configuration review' -DimLine 'Read the table carefully before you confirm — especially disk scope and USB options.'

    $passDisplay = if (-not $AccountPasswordProvided) { '[silver](not set)[/]' } else { '[silver]********[/] [dim](hidden)[/]' }
    $regionalLine = if ($MirrorHostRegional) {
        '[green]Same as this PC[/] [dim](time zone, locales, keyboard)[/]'
    }
    else {
        '[yellow]Custom (gold image)[/]'
    }
    $diskModeValue = if (-not $AutoWipeDisk) {
        '[green]Manual — Setup disk UI (autounattend does not clear disks)[/]'
    }
    else {
        '[bold red]Unattended[/] [dim]— primary disk: one Windows volume for the whole disk[/]'
    }
    $diskExtra = Get-Win11IsoDiskLayoutExtraMarkup -AutoWipeDisk:$AutoWipeDisk
    $cursorRow = '[cyan]Windows 11 Modern[/] [dim](bundled WinMint default)[/]'
    $driverRow = switch ($DriverMode) {
        'Host'   { '[cyan]Mirror this PC[/] [dim](Export-WindowsDriver)[/]' }
        'Custom' { "[cyan]Custom path[/] [dim]$DriverPath[/]" }
        default  { '[silver]None[/]' }
    }
    $desktopLayers = [System.Collections.Generic.List[string]]::new()
    if ($InstallWindhawk) { $desktopLayers.Add('Windhawk') | Out-Null }
    if ($InstallYasb) { $desktopLayers.Add('YASB') | Out-Null }
    if ($InstallKomorebi) { $desktopLayers.Add('Komorebi') | Out-Null }
    $desktopRow = if ($desktopLayers.Count) {
        "[green]$($desktopLayers -join ', ')[/]"
    }
    else {
        '[silver]Standard Windows[/]'
    }

    $tree = [Spectre.Console.Tree]::new('[bold white]Build profile[/]')

    $srcNode = $tree.AddNode('[bold cyan3]Source media[/]')
    $srcNode.AddNode("ISO [dim]·[/] [cyan]$($SourceIsoPath)[/]") | Out-Null
    $srcNode.AddNode("Architecture [dim]·[/] [cyan]$TargetArchitecture[/] [dim](file name / install.wim)[/]") | Out-Null

    $idNode = $tree.AddNode('[bold cyan3]Account & identity[/]')
    $idNode.AddNode("Computer [dim]·[/] [green]$ComputerName[/]") | Out-Null
    $idNode.AddNode("User [dim]·[/] [green]$UserName[/]") | Out-Null
    $idNode.AddNode("Password [dim]·[/] $passDisplay") | Out-Null
    $idNode.AddNode("Autologon [dim]·[/] $(if ($AutoLogon) { '[green]Yes[/]' } else { '[silver]No[/]' })") | Out-Null

    $edNode = $tree.AddNode('[bold cyan3]Edition & regional[/]')
    $edNode.AddNode("Edition [dim]·[/] [green]$EditionName[/]") | Out-Null
    $edNode.AddNode("Regional [dim]·[/] $regionalLine") | Out-Null
    $edNode.AddNode("Time zone [dim]·[/] [cyan]$TimeZoneId[/]") | Out-Null
    $edNode.AddNode("UI language [dim]·[/] [cyan]$UILanguage[/]") | Out-Null
    $edNode.AddNode("User locale [dim]·[/] [cyan]$UserLocale[/]") | Out-Null
    $edNode.AddNode("Input locale [dim]·[/] [cyan]$InputLocale[/]") | Out-Null
    $edNode.AddNode("Cursor [dim]·[/] $cursorRow") | Out-Null

    $deskNode = $tree.AddNode('[bold cyan3]Desktop[/]')
    $deskNode.AddNode("Layers [dim]·[/] $desktopRow") | Out-Null
    $deskNode.AddNode("Drivers [dim]·[/] $driverRow") | Out-Null

    $diskNode = $tree.AddNode('[bold cyan3]Target disk[/]')
    $diskNode.AddNode("Mode [dim]·[/] $diskModeValue") | Out-Null
    if ($AutoWipeDisk -and -not [string]::IsNullOrWhiteSpace($diskExtra)) {
        $diskNode.AddNode("Notes [dim]·[/] $diskExtra") | Out-Null
    }

    Write-SpectreSpacing
    [Spectre.Console.AnsiConsole]::Write($tree)
    Write-SpectreSpacing

    if ($AutoWipeDisk) {
        Write-SpectreSpacing
        $diskWarnRenderable = @(
            '[red]Unattended Setup will remove every partition on the [bold]primary disk[/] [red]and recreate EFI, MSR, and a Windows volume. All data on that disk is destroyed.[/]'
            '[silver]Dual-boot templates leave trailing space[/] [green]unallocated[/] [silver]for another OS; nominal 1 TB / 2 TB sizes are baked in — edit[/] [cyan]autounattend.xml[/] [silver]if your disk differs.[/]'
            '[darkorange]Boot this installer only on hardware you intend to erase, or switch to manual disk mode in autounattend before broad deployment.[/]'
        ) | Format-SpectreRows
        $null = Format-SpectrePanel -Data $diskWarnRenderable -Header '[bold red]WARNING — Target disk[/]' -Border Rounded -Color Red -Expand | Out-SpectreHost | Out-Host
        $diskAckBody = @(
            '[red]The ISO you are building includes[/] [bold]autounattend[/] [red]disk steps that run during Setup without another prompt.[/]'
            '[silver]Typing YES means you accept total data loss on that disk if this media boots on the wrong machine.[/]'
        ) | Format-SpectreRows
        if (-not (Confirm-Win11IsoTypedDestructiveAcknowledgment -PanelHeader '[bold red]Typed confirmation — primary disk[/]' -PanelBodyMarkup $diskAckBody -RequiredPhrase 'YES')) {
            return [pscustomobject]@{ Proceed = $false; PostBuildUsbDriveLetter = $null }
        }
    }

    $postUsbLetter = $null
    $usbList = @(Get-RemovableUsbVolumeCandidate)
    if (-not $DryRun -and $usbList.Count -ge 1) {
        Write-SectionHeader 'After build: USB install media'
        # Plain-text choices only: Read-SpectreSelection return values must not be matched against Spectre-markup labels (markup is often normalized or stripped).
        $usbSkip = 'No — keep only the ISO file (skip USB)'
        $usbChoices = @($usbSkip) + (
            $usbList | ForEach-Object {
                "Removable USB on drive $($_.DriveLetter): — $($_.SizeGb) GB total · $($_.FreeGb) GB free"
            }
        )
        $usbPick = Read-SpectreSelection `
            -Message "[bold]Copy the finished ISO to a USB drive?[/]`n[dim]The physical disk behind the volume you pick is erased when the stick is prepared.[/]" `
            -Choices $usbChoices -EnableSearch -PageSize $script:Win11IsoSpectrePageSizeList
        if ($usbPick -ne $usbSkip) {
            $pickedLetter = $null
            if ($usbPick -match '(?i)Removable USB on drive\s+([A-Za-z])\s*:') {
                $pickedLetter = $Matches[1].ToUpperInvariant()
            }
            $match = if ($pickedLetter) {
                $usbList | Where-Object { ([string]$_.DriveLetter).ToUpperInvariant() -ceq $pickedLetter } | Select-Object -First 1
            }
            else { $null }
            if ($null -ne $match) {
                Write-SpectreSpacing
                $usbExplain = @(
                    "[bold red]Entire physical disk[/] [white]behind volume[/] [bold yellow]$($match.DriveLetter):[/] [white]will be erased[/] [silver](Clear-Disk: all partitions removed).[/]"
                    '[silver]Then:[/] [cyan]GPT[/][silver],[/] [cyan]one NTFS partition[/][silver],[/] [cyan]ISO files copied[/] [silver]— same as a clean USB installer factory image.[/]'
                    '[darkorange]Anything currently on that USB stick or card is destroyed.[/] [dim]Letter may change after formatting.[/]'
                    ''
                    '[bold yellow]Default is No[/] [silver]— keep ISO only and skip USB preparation.[/]'
                ) | Format-SpectreRows
                $null = Format-SpectrePanel -Data $usbExplain -Header '[bold red]Confirm USB target[/]' -Border Double -Color Red -Expand | Out-SpectreHost | Out-Host
                Write-SpectreSpacing
                $usbPickStream = @(Read-SpectreConfirm -Message "[bold red]Wipe that whole disk[/] [silver]after the build finishes and copy the ISO onto it?[/]" -DefaultAnswer n `
                        -ConfirmSuccess '[green]USB target locked in for after the build.[/]' `
                        -ConfirmFailure '[yellow]USB preparation cancelled — ISO only.[/]')
                $usbPickBools = @($usbPickStream | Where-Object { $_ -is [bool] })
                $usbEraseOk = if ($usbPickBools.Count -ge 1) { [bool]$usbPickBools[-1] } else { $false }
                if ($usbEraseOk) {
                    $usbAckBody = @(
                        "[bold red]After the build[/], the script will run [bold]Clear-Disk[/] on the physical device behind [bold yellow]$($match.DriveLetter):[/][red].[/]"
                        '[silver]You must type the phrase exactly to authorize that erase (same as other destructive steps in this wizard).[/]'
                    ) | Format-SpectreRows
                    if (Confirm-Win11IsoTypedDestructiveAcknowledgment -PanelHeader '[bold red]Typed confirmation — USB erase[/]' -PanelBodyMarkup $usbAckBody -RequiredPhrase 'YES') {
                        $postUsbLetter = $match.DriveLetter
                    }
                    else {
                        $null = Format-SpectrePanel -Data '[yellow]USB preparation cancelled — ISO only.[/]' -Header '[bold yellow]USB[/]' -Border Rounded -Color Yellow -Expand | Out-SpectreHost | Out-Host
                    }
                }
            }
            else {
                LogWarn 'USB volume choice did not match any removable drive letter (selection text changed unexpectedly). USB preparation will not run after the build.'
            }
        }
    }
    elseif ($DryRun) {
        Write-SectionHeader 'USB (dry-run detection)'
        if ($usbList.Count -ge 1) {
            $usbLines = ($usbList | ForEach-Object { $_.Label }) -join "`n"
            $usbPanel = "[green]Removable USB volume(s) on this PC:[/] [dim]($($usbList.Count))[/]`n$usbLines`n[dim]Dry run does not prepare USB media; a full build would offer that step after the ISO is written.[/]"
            $null = Format-SpectrePanel -Data $usbPanel -Header '[bold grey]Detected[/]' -Border Rounded -Color Grey -Expand | Out-SpectreHost | Out-Host
        }
        else {
            $usbMissing = @(
                '[yellow]No removable USB volumes detected[/]'
                '[dim]Windows reported no [grey]Removable[/] drive with an assigned letter.'
                'A full build can still produce an ISO only; insert USB before build for the optional copy.[/]'
            ) -join ' '
            $null = Format-SpectrePanel -Data $usbMissing `
                -Header '[bold grey]USB[/]' -Border Rounded -Color Grey -Expand | Out-SpectreHost | Out-Host
        }
    }

    Write-SpectreSpacing
    # Read-SpectreConfirm may emit host renderables before the final boolean; capture only booleans from the output stream.
    $confirmMsg = if ($DryRun) {
        '[bold]Start dry-run verification with these settings?[/] [grey](Staged ISO, WIM metadata, boot files, prerequisites; no WIM customization or output ISO.)[/]'
    }
    else {
        '[bold]Start the unattended build with these settings?[/] [grey](Expect a long run.)[/]'
    }
    $confirmOk = if ($DryRun) { '[green]Starting dry run…[/]' } else { '[green]Starting build…[/]' }
    $confirmFail = if ($DryRun) { '[yellow]Dry run cancelled.[/]' } else { '[yellow]Build cancelled.[/]' }
    $confirmStream = @(Read-SpectreConfirm -Message $confirmMsg -DefaultAnswer y `
            -ConfirmSuccess $confirmOk `
            -ConfirmFailure $confirmFail)
    $boolResults = @($confirmStream | Where-Object { $_ -is [bool] })
    $go = if ($boolResults.Count -ge 1) { [bool]$boolResults[-1] } else { $false }
    return [pscustomobject]@{ Proceed = $go; PostBuildUsbDriveLetter = $postUsbLetter }
}

function Invoke-FlashWindowsInstallMediaToUsb {
    <#
    <summary>
    Wipes the USB disk backing the chosen drive letter, formats NTFS, and
    copies the mounted ISO root. -SkipTypedDestructiveAck is for wizard calls
    that already required typing YES for this USB target.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][ValidateLength(1, 1)][string]$SourceRemovableDriveLetter,
        [switch]$SkipTypedDestructiveAck
    )
    $letter = $SourceRemovableDriveLetter.ToUpperInvariant()
    $vol = Get-Volume -DriveLetter $letter -ErrorAction Stop
    if ($vol.DriveType -ne 'Removable') {
        throw "Drive ${letter}: is not a Removable volume; refusing to erase."
    }

    $isoItem = Get-Item -LiteralPath $IsoPath -ErrorAction Stop
    $isoBytes = $isoItem.Length
    if ($isoBytes -gt $vol.Size) {
        throw "ISO ($([math]::Round($isoBytes / 1GB, 2)) GB) is larger than the USB device ($([math]::Round($vol.Size / 1GB, 2)) GB)."
    }

    if (-not $SkipTypedDestructiveAck) {
        $usbFlashAckBody = @(
            "[bold red]The physical disk behind[/] [bold yellow]${letter}:[/] [red]will be cleared[/] [silver](all partitions removed), then formatted and filled with the ISO file tree.[/]"
            '[silver]Type the phrase exactly to proceed, or cancel with an empty line.[/]'
        ) | Format-SpectreRows
        if (-not (Confirm-Win11IsoTypedDestructiveAcknowledgment -PanelHeader '[bold red]Typed confirmation — USB install media[/]' -PanelBodyMarkup $usbFlashAckBody -RequiredPhrase 'YES')) {
            $null = Format-SpectrePanel -Data '[yellow]USB copy skipped.[/]' -Header '[bold yellow]USB[/]' -Border Rounded -Color Yellow -Expand | Out-SpectreHost | Out-Host
            return
        }
    }

    Write-SectionHeader 'USB install drive'
    Invoke-Action "Preparing USB (disk behind ${letter}: will be erased; source ISO mounted for copy)" {
        LogVerbose $IsoPath
        $part0 = Get-Partition -DriveLetter $letter -ErrorAction Stop
        $diskNumber = $part0.DiskNumber

        $oldPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            $iso = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
            $volume = $iso | Get-Volume -ErrorAction Stop | Select-Object -First 1
            if (-not $volume) { throw 'Could not obtain a readable volume for the mounted ISO.' }
            $srcRoot = if ($volume.DriveLetter) {
                "$($volume.DriveLetter):\"
            }
            elseif ($volume.Path) {
                $volume.Path
            }
            else {
                throw 'Could not obtain a drive letter or volume path for the mounted ISO.'
            }
            try {
                Log "Erasing USB disk $diskNumber and creating one NTFS partition…"
                Clear-Disk -Number $diskNumber -RemoveData -Confirm:$false -ErrorAction Stop
                Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop
                $newPart = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
                $null = Format-Volume -Partition $newPart -FileSystem NTFS -NewFileSystemLabel 'W11_SETUP' -Confirm:$false -ErrorAction Stop
                $destLetter = (Get-Partition -DiskNumber $diskNumber | Where-Object { $_.DriveLetter } | Select-Object -First 1 -ExpandProperty DriveLetter)
                if (-not $destLetter) { throw 'No drive letter assigned to the new USB partition.' }
                $destRoot = "$destLetter`:\"
                Log "Copying ISO files to ${destRoot}…"
                LogVerbose 'robocopy /E /MT:16 (quiet headers)'
                $null = & robocopy.exe "$srcRoot" "$destRoot" /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /MT:16 /NFL /NDL /NJH /NJS
                $rc = $LASTEXITCODE
                if ($rc -ge 8) { throw "robocopy to USB failed with exit code $rc" }
                LogOK "Bootable USB install media is ready at ${destRoot}."
            }
            finally {
                Dismount-Win11IsoDiskImageLiteral -LiteralImagePath $IsoPath
            }
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $oldPref
        }
    }
}
