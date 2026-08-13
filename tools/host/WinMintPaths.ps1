#requires -Version 7.6
Set-StrictMode -Version Latest

function Get-WinMintGateBWorkDirectory {
    Join-Path $env:LOCALAPPDATA 'WinMint\work\gate-b'
}

function Get-WinMintScratchWorkDirectory {
    Join-Path $env:LOCALAPPDATA 'WinMint\work\scratch'
}

function Get-WinMintHostPreparedMediaRoot {
    Join-Path $env:ProgramData 'WinMint\Servicing\media-cache'
}
