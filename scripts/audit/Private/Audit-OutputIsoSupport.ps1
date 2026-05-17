#Requires -Version 7.3
# Dot-sourced by scripts\audit\Audit-OutputIso.ps1 — not an entry point.

function Add-AuditLine {
    param([string]$Text)
    [void]$script:AuditLines.Add($Text)
    if (-not $script:AuditJsonOutput) {
        Write-Host $Text
    }
}

function Add-AuditFinding {
    param(
        [ValidateSet('Info', 'Warning', 'Error')][string]$Severity,
        [string]$Section,
        [string]$Message
    )
    $o = [pscustomobject]@{ Severity = $Severity; Section = $Section; Message = $Message }
    [void]$script:AuditFindings.Add($o)
    $prefix = switch ($Severity) {
        'Error' { '[ERR] ' }
        'Warning' { '[WRN] ' }
        default { '[INF] ' }
    }
    Add-AuditLine -Text ("{0}{1} | {2}" -f $prefix, $Section, $Message)
}

function Test-WinWSElevation {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-WinWSRepositoryRoot {
    param([string]$Candidate)
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }
# This file lives in scripts\audit\Private; repo root is scripts\..\.. — avoid Split-Path -LiteralPath -Parent
    # (some hosts mis-resolve that parameter set). Use directory name of this script's folder.
    $privateDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($privateDir)) {
        throw 'PSScriptRoot is empty in Audit-OutputIsoSupport.ps1; cannot resolve repository root.'
    }
    $scriptsDir = [System.IO.Path]::GetDirectoryName($privateDir.TrimEnd([char]'/', [char]'\'))
    if ([string]::IsNullOrWhiteSpace($scriptsDir)) {
        throw "Could not resolve parent of '$privateDir'."
    }
    return (Resolve-Path -LiteralPath (Join-Path $scriptsDir '..')).Path
}

function Get-WinWSNewestOutputIso {
    param([string]$OutDir)
    Get-ChildItem -LiteralPath $OutDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-Iso9660PrimaryVolumeId {
    param([Parameter(Mandatory)][string]$LiteralIsoPath)
    try {
        $fs = [IO.File]::OpenRead($LiteralIsoPath)
        $buf = New-Object byte[] 2048
        [void]$fs.Seek(16 * 2048, [IO.SeekOrigin]::Begin)
        [void]$fs.Read($buf, 0, 2048)
        $fs.Close()
        if ([Text.Encoding]::ASCII.GetString($buf, 1, 5) -ne 'CD001') {
            return $null
        }
        return [Text.Encoding]::ASCII.GetString($buf, 40, 32).Trim()
    }
    catch {
        return $null
    }
}

function Test-AuditPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Section,
        [string]$Label = ''
    )
    $full = Join-Path $Root $RelativePath
    $ok = Test-Path -LiteralPath $full
    $name = if ($Label) { $Label } else { $RelativePath }
    if ($ok) {
        Add-AuditFinding -Severity Info -Section $Section -Message "OK: $name"
    }
    else {
        Add-AuditFinding -Severity Error -Section $Section -Message "Missing: $name ($RelativePath)"
    }
    return $ok
}

function Get-UnattendPassSummary {
    param([Parameter(Mandatory)][xml]$Doc)
    $passes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $Doc.SelectNodes("//*[local-name()='settings' and @pass]")) {
        [void]$passes.Add([string]$n.pass)
    }
    return @($passes | Sort-Object)
}
