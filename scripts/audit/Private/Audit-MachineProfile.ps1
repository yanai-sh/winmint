#Requires -Version 7.3
# Dot-sourced by scripts\audit\Audit-OutputIso.ps1

function Invoke-WinWSMachineProfileAudit {
    param(
        [Parameter(Mandatory)][object]$MachineProfile,
        [object]$Manifest,
        [string]$IsoRoot,
        [object[]]$InstallImageRows,
        [string]$InstallArchFromWim,
        [int]$WimIndex,
        [switch]$AssertHostMatches
    )

    $fn = [string]$MachineProfile.friendlyName
    if ([string]::IsNullOrWhiteSpace($fn)) { $fn = 'Machine profile' }
    Add-AuditLine ''
    Add-AuditLine ("--- Machine profile: {0} ---" -f $fn)

    if ($AssertHostMatches -and $MachineProfile.PSObject.Properties['optionalSystemModelContains']) {
        $needle = [string]$MachineProfile.optionalSystemModelContains
        if (-not [string]::IsNullOrWhiteSpace($needle)) {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $model = [string]$cs.Model
            if ($model -notlike ('*' + $needle + '*')) {
                Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                    -Message ("This PC model '{0}' does not contain optionalSystemModelContains '{1}'." -f $model, $needle)
            }
            else {
                Add-AuditFinding -Severity Info -Section 'MachineProfile' -Message ("Host model OK: {0}" -f $model)
            }
        }
    }

    $reqArch = [string]$MachineProfile.processorArchitecture
    if (-not [string]::IsNullOrWhiteSpace($reqArch)) {
        if ($InstallArchFromWim -ne $reqArch) {
            Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                -Message ("install.wim architecture is '{0}' but profile requires '{1}'." -f $InstallArchFromWim, $reqArch)
        }
        else {
            Add-AuditFinding -Severity Info -Section 'MachineProfile' -Message ("Architecture OK: {0}" -f $InstallArchFromWim)
        }
    }

    $row = $InstallImageRows | Where-Object { [int]$_.ImageIndex -eq $WimIndex } | Select-Object -First 1
    if (-not $row) {
        Add-AuditFinding -Severity Error -Section 'MachineProfile' `
            -Message ("No install image at index {0} (profile installWimImageIndex)." -f $WimIndex)
        return
    }

    if ($MachineProfile.PSObject.Properties['expectedInstallImageName']) {
        $exp = [string]$MachineProfile.expectedInstallImageName
        if (-not [string]::IsNullOrWhiteSpace($exp)) {
            $actual = [string]$row.ImageName
            if (-not $actual.Equals($exp, [StringComparison]::OrdinalIgnoreCase)) {
                Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                    -Message ("Index {0}: image name is '{1}' but profile expected '{2}'." -f $WimIndex, $actual, $exp)
            }
            else {
                Add-AuditFinding -Severity Info -Section 'MachineProfile' `
                    -Message ("Index {0} edition name OK: {1}" -f $WimIndex, $actual)
            }
        }
    }

    if ($MachineProfile.PSObject.Properties['expectedInstallImageNameMustNotContain']) {
        $actual = [string]$row.ImageName
        foreach ($bad in @($MachineProfile.expectedInstallImageNameMustNotContain)) {
            $b = [string]$bad
            if ([string]::IsNullOrWhiteSpace($b)) { continue }
            if ($actual -like ('*' + $b + '*')) {
                Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                    -Message ("Image name must not contain '{0}' (profile exclusion list)." -f $b)
            }
        }
    }

    if ($MachineProfile.PSObject.Properties['requireEfiLoaderPath'] -and -not [string]::IsNullOrWhiteSpace($IsoRoot)) {
        $rel = [string]$MachineProfile.requireEfiLoaderPath
        $efiFull = Join-Path $IsoRoot $rel
        if (-not (Test-Path -LiteralPath $efiFull)) {
            Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                -Message ("Missing EFI file required by profile: {0}" -f $rel)
        }
        else {
            Add-AuditFinding -Severity Info -Section 'MachineProfile' -Message ("EFI path OK: {0}" -f $rel)
        }
    }

    if ($null -ne $Manifest) {
        if ($MachineProfile.PSObject.Properties['requireManifestDriverSource']) {
            $r = [string]$MachineProfile.requireManifestDriverSource
            if (-not [string]::IsNullOrWhiteSpace($r)) {
                $src = [string]$Manifest.drivers.source
                if ($src -ne $r) {
                    Add-AuditFinding -Severity Error -Section 'MachineProfile' `
                        -Message ("Build manifest drivers.source is '{0}' but profile requires '{1}'." -f $src, $r)
                }
                else {
                    Add-AuditFinding -Severity Info -Section 'MachineProfile' -Message ("Manifest drivers.source OK: {0}" -f $src)
                }
            }
        }
        if ($MachineProfile.PSObject.Properties['minimumManifestInjectedInfs']) {
            try {
                $min = [int]$MachineProfile.minimumManifestInjectedInfs
                if ($min -gt 0) {
                    $cnt = [int]$Manifest.drivers.injectedCount
                    if ($cnt -lt $min) {
                        Add-AuditFinding -Severity Warning -Section 'MachineProfile' `
                            -Message ("Manifest drivers.injectedCount ({0}) is below profile minimum ({1})." -f $cnt, $min)
                    }
                    else {
                        Add-AuditFinding -Severity Info -Section 'MachineProfile' `
                            -Message ("Manifest injected INF count OK: {0} (>={1})" -f $cnt, $min)
                    }
                }
            }
            catch { }
        }
    }
    else {
        Add-AuditFinding -Severity Warning -Section 'MachineProfile' -Message 'No WinWS-BuildManifest.json loaded; skipped manifest-based machine checks.'
    }
}
