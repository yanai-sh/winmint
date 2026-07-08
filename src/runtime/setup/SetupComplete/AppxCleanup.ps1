# SetupComplete machine-phase module: enforce offline AppX removal on the live image
# before the first user session starts. Some inbox apps can survive provisioning
# cleanup and still appear in the first interactive profile, so this pass removes
# the matching provisioned and installed packages from the staged image as a
# second line of defense.

function Invoke-ScAppxRemoval {
    $prefixes = @()
    if ($setupProfile -and $setupProfile.PSObject.Properties['appxRemovalPrefixes']) {
        $prefixes = @($setupProfile.appxRemovalPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    $aiPrefixes = @()
    if ($setupProfile -and $setupProfile.PSObject.Properties['aiRemoval'] -and $setupProfile.aiRemoval.PSObject.Properties['appxPrefixes']) {
        $aiPrefixes = @($setupProfile.aiRemoval.appxPrefixes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    if ($aiPrefixes.Count -gt 0) {
        $prefixes = @($prefixes | Where-Object { $_ -notin $aiPrefixes })
    }
    if ($prefixes.Count -eq 0) {
        Write-ScLog 'AppX cleanup skipped: no removal prefixes were staged.'
        return
    }

    $reportPath = Join-Path $logDir 'SetupComplete_AppxCleanup.json'
    $result = [ordered]@{
        generatedAt = Get-Date -Format o
        prefixes = @($prefixes)
        removedProvisioned = @()
        removedInstalled = @()
        failed = @()
    }

    Write-ScLog "AppX cleanup starting for $($prefixes.Count) prefix(es)."

    $maxAttempts = 12
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $attemptRemoved = 0

        foreach ($pkg in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)) {
            $displayName = [string]$pkg.DisplayName
            $packageName = [string]$pkg.PackageName
            if ([string]::IsNullOrWhiteSpace($displayName) -and [string]::IsNullOrWhiteSpace($packageName)) { continue }
            if (-not ($prefixes | Where-Object { $displayName -like "*$_*" -or $packageName -like "*$_*" })) { continue }
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop | Out-Null
                $result.removedProvisioned += [ordered]@{
                    displayName = $displayName
                    packageName = $packageName
                }
                $attemptRemoved++
            }
            catch {
                $result.failed += [ordered]@{
                    kind = 'provisioned'
                    name = $displayName
                    packageName = $packageName
                    error = [string]$_.Exception.Message
                }
                Write-ScLog "AppX cleanup failed for provisioned package $displayName ($packageName): $($_.Exception.Message)"
            }
        }

        foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
            $name = [string]$pkg.Name
            $packageFullName = [string]$pkg.PackageFullName
            if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($packageFullName)) { continue }
            if (-not ($prefixes | Where-Object { $name -like "*$_*" -or $packageFullName -like "*$_*" })) { continue }
            try {
                Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
                $result.removedInstalled += [ordered]@{
                    name = $name
                    packageFullName = $packageFullName
                }
                $attemptRemoved++
            }
            catch {
                $result.failed += [ordered]@{
                    kind = 'installed'
                    name = $name
                    packageFullName = $packageFullName
                    error = [string]$_.Exception.Message
                }
                Write-ScLog "AppX cleanup failed for installed package $name ($packageFullName): $($_.Exception.Message)"
            }
        }

        $remaining = @(
            foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
                $name = [string]$pkg.Name
                $packageFullName = [string]$pkg.PackageFullName
                if (-not ($prefixes | Where-Object { $name -like "*$_*" -or $packageFullName -like "*$_*" })) { continue }
                [string]$packageFullName
            }
        )
        if ($remaining.Count -eq 0) { break }
        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds 10
        }
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-ScLog "AppX cleanup finished: provisioned=$(@($result.removedProvisioned).Count) installed=$(@($result.removedInstalled).Count) failed=$(@($result.failed).Count)"
}
