#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Get-WimMetadata.ps1')

$sample = @'
Deployment Image Servicing and Management tool
Version: 10.0.26100.1

Details for image : C:\media\sources\install.wim

Index : 3
Name : Windows 11 Pro
Description : Windows 11 Pro
Size : 15,000,000,000 bytes
Architecture : ARM64
Hal : acpiapic
Version : 10.0.26100.1
ServicePack Build : 26100
ServicePack Level : 0
Edition : Professional
Installation : Client
ProductType : WinNT
ProductSuite : Terminal Server
Languages : en-US
System Root : WINDOWS
Directories : 30000
Files : 100000
Created : 1/1/2025 - 12:00:00 AM
Modified : 1/2/2025 - 12:00:00 AM

The operation completed successfully.
'@

$parsed = ConvertFrom-WimInfoText -Text $sample -Index 3
if ($parsed.IndexCount -ne 1) { throw "Test-WimMetadata: expected IndexCount 1, got $($parsed.IndexCount)" }
if ($parsed.Installation -ne 'Client') { throw 'Test-WimMetadata: Installation' }
if ($parsed.ProductType -ne 'WinNT') { throw 'Test-WimMetadata: ProductType' }
if ((Resolve-WimEditionId -Snapshot $parsed) -ne 'Professional') { throw 'Test-WimMetadata: EditionId from Edition' }

$multi = @'
Index : 1
Name : Windows 11 Home
Architecture : ARM64
Edition : Core
ServicePack Build : 26100

Index : 3
Name : Windows 11 Pro
Architecture : ARM64
Edition : Professional
Installation : Client
ProductType : WinNT
ProductSuite : Terminal Server
ServicePack Build : 26100
'@
$homeSnap = ConvertFrom-WimInfoText -Text $multi -Index 1
$proSnap = ConvertFrom-WimInfoText -Text $multi -Index 3
if ($homeSnap.IndexCount -ne 2) { throw "Test-WimMetadata: expected IndexCount 2" }
if ($homeSnap.Name -ne 'Windows 11 Home') { throw "Test-WimMetadata: Home name" }
if ($proSnap.Name -ne 'Windows 11 Pro') { throw "Test-WimMetadata: Pro name" }
if ($proSnap.Architecture -ne 'ARM64') { throw "Test-WimMetadata: arch" }
if ($proSnap.Edition -ne 'Professional') { throw "Test-WimMetadata: edition" }
if ($proSnap.Build -ne '26100') { throw "Test-WimMetadata: build" }

$list = ConvertFrom-WimInfoListText -Text $multi
if ($list.Count -ne 2) { throw "Test-WimMetadata: list count $($list.Count)" }
if ($list[0].index -ne 1 -or $list[0].name -ne 'Windows 11 Home') { throw 'Test-WimMetadata: list Home' }
if ($list[1].index -ne 3 -or $list[1].edition -ne 'Professional') { throw 'Test-WimMetadata: list Pro' }
$listJson = Write-WimIndexListJson -Rows $list
if ($listJson -notmatch '"index"\s*:\s*1') { throw "Test-WimMetadata: list JSON`n$listJson" }

$badList = @'
Index : 1
Name : <undefined>
Architecture : ARM64
Edition : Core
'@
$threw = $false
try { ConvertFrom-WimInfoListText -Text $badList | Out-Null } catch { $threw = $true }
if (-not $threw) { throw 'Test-WimMetadata: expected list refuse on <undefined> Name' }

Assert-WimMetadataStable -Before $proSnap -After $proSnap -Context 'Test-WimMetadata identity'

$beforeUbr = [ordered]@{
    Name = 'Windows 11 Pro'; Architecture = 'ARM64'; Edition = 'Professional'
    Installation = 'Client'; ProductType = 'WinNT'; ProductSuite = 'Terminal Server'; Languages = 'en-US'
    Build = '8037'
}
$afterUbr = [ordered]@{
    Name = 'Windows 11 Pro'; Architecture = 'ARM64'; Edition = 'Professional'
    Installation = 'Client'; ProductType = 'WinNT'; ProductSuite = 'Terminal Server'; Languages = 'en-US'
    Build = '9168'
}
Assert-WimMetadataStable -Before $beforeUbr -After $afterUbr -Context 'Test-WimMetadata ubr increase'

$downUbr = [ordered]@{}
foreach ($k in $afterUbr.Keys) { $downUbr[$k] = $afterUbr[$k] }
$downUbr['Build'] = '8000'
$threw = $false
try { Assert-WimMetadataStable -Before $beforeUbr -After $downUbr -Context 'Test-WimMetadata ubr down' } catch { $threw = $true }
if (-not $threw) { throw 'Test-WimMetadata: expected assert throw on UBR decrease' }


$badName = [ordered]@{ Name = '<undefined>'; Architecture = 'ARM64'; Edition = 'Professional'; Installation = 'Client'; ProductType = 'WinNT'; Build = '26100' }
$threw = $false
try { Assert-WimMetadataStable -Before $proSnap -After $badName -Context 'Test-WimMetadata bad name' } catch { $threw = $true }
if (-not $threw) { throw 'Test-WimMetadata: expected assert throw on <undefined> Name' }

$badEdition = [ordered]@{
    Name = 'Windows 11 Pro'; Architecture = 'ARM64'; Edition = '<undefined>'
    Installation = 'Client'; ProductType = 'WinNT'; Build = '26100'
}
$threw = $false
try { Assert-WimMetadataPresent -Snapshot $badEdition -Context 'Test-WimMetadata bad edition' } catch { $threw = $true }
if (-not $threw) { throw 'Test-WimMetadata: expected assert throw on <undefined> Edition' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-ei-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'sources') | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $tmp 'sources\PID.txt') -Value 'stale' -Encoding utf8
    Write-WinMintEditionConfig -MediaDir $tmp -Snapshot $proSnap
    if (Test-Path -LiteralPath (Join-Path $tmp 'sources\PID.txt')) { throw 'Test-WimMetadata: PID.txt should be removed' }
    $ei = Get-Content -LiteralPath (Join-Path $tmp 'sources\ei.cfg') -Raw
    if ($ei -notmatch '\[EditionID\]\r?\nProfessional') { throw "Test-WimMetadata: ei.cfg EditionID`n$ei" }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$fromName = Resolve-WimEditionId -Snapshot ([ordered]@{ Name = 'Windows 11 Pro'; Edition = $null })
if ($fromName -ne 'Professional') { throw 'Test-WimMetadata: EditionId from Name' }

$ltsc = Resolve-WimEditionId -Snapshot ([ordered]@{ Name = 'Windows 11 Enterprise LTSC'; Edition = $null })
if ($ltsc -ne 'EnterpriseS') { throw "Test-WimMetadata: Enterprise LTSC EditionId got '$ltsc'" }
$iot = Resolve-WimEditionId -Snapshot ([ordered]@{ Name = 'Windows 11 IoT Enterprise LTSC'; Edition = $null })
if ($iot -ne 'IoTEnterpriseS') { throw "Test-WimMetadata: IoT Enterprise LTSC EditionId got '$iot'" }
$ws = Resolve-WimEditionId -Snapshot ([ordered]@{ Name = 'Windows 11 Pro for Workstations'; Edition = $null })
if ($ws -ne 'ProfessionalWorkstation') { throw "Test-WimMetadata: Pro for Workstations EditionId got '$ws'" }

# Probe child runs before ServicingPlan sets WINMINT_SERVICING_WORK (dd6abfa).
$savedDismWork = $env:WINMINT_SERVICING_WORK
try {
    $env:WINMINT_SERVICING_WORK = ''
    $threw = $false
    try { Get-WimIndexList -WimFile 'C:\winmint-no-such.wim' | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw 'Test-WimMetadata: expected wimMissing when WIM absent' }
    if ($env:WINMINT_SERVICING_WORK -notmatch '[\\/]wim-probe$') {
        throw "Test-WimMetadata: expected probe work default, got '$($env:WINMINT_SERVICING_WORK)'"
    }

    # Reach DISM with probe default — must not fail-closed on missing env (smoke Apply regression).
    $dismThrew = $false
    $dismMsg = ''
    try {
        Invoke-WinMintDism -ArgumentList @('/English', '/Get-WimInfo', '/WimFile:C:\winmint-no-such.wim') `
            -Stage 'wim-probe-gate' -PassThruText | Out-Null
    }
    catch {
        $dismThrew = $true
        $dismMsg = $_.Exception.Message
    }
    if (-not $dismThrew) { throw 'Test-WimMetadata: expected DISM fail on missing WIM' }
    if ($dismMsg -match 'WINMINT_SERVICING_WORK is unset') {
        throw "Test-WimMetadata: probe work not applied before DISM: $dismMsg"
    }

    # Child -File -ListFromIso (Orchestrator spawn). No real ISO — just check never mounts (maintainer-host.json).
    $env:WINMINT_SERVICING_WORK = ''
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    [void]$psi.ArgumentList.Add('-NoProfile')
    [void]$psi.ArgumentList.Add('-File')
    [void]$psi.ArgumentList.Add((Join-Path $repo 'servicing\Get-WimMetadata.ps1'))
    [void]$psi.ArgumentList.Add('-ListFromIso')
    [void]$psi.ArgumentList.Add('C:\winmint-no-such.iso')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stderr = $proc.StandardError.ReadToEnd()
    $null = $proc.StandardOutput.ReadToEnd()
    if (-not $proc.WaitForExit(60000)) { throw 'Test-WimMetadata: ListFromIso child timed out' }
    if ($proc.ExitCode -eq 0) { throw 'Test-WimMetadata: ListFromIso child should fail on missing ISO' }
    if ($stderr -notmatch 'wim\.probe\.isoMissing') {
        throw "Test-WimMetadata: expected isoMissing from child, got: $stderr"
    }
    if ($stderr -match 'WINMINT_SERVICING_WORK is unset') {
        throw "Test-WimMetadata: child hit unset-env: $stderr"
    }
}
finally {
    $env:WINMINT_SERVICING_WORK = $savedDismWork
}

Write-Output 'Test-WimMetadata ok'
exit 0
