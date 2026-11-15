#requires -Version 7.6
# AppX pins come from the bound RemoveProvisionedAppx stage. No Profile, no Hyper-V.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\Assert-DebloatDigestPins.ps1')

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -match 'profileDoc\.debloat') {
    throw 'Invoke-Smoke must not fall back to Profile debloat for AppX pins'
}
if ($smoke -match '\$pinnedOnlineRemoveAppx = @\(\$pinnedRemoveAppx\)') {
    throw 'Invoke-Smoke must not treat the offline remove list as online pins'
}
if ($smoke -notmatch '\$pinnedOnlineRemoveAppx = @\(\)') {
    throw 'Invoke-Smoke online AppX pins stay empty; stage ids stay on PinnedRemoveAppx'
}

function New-StagesFile {
    param([string] $Dir, [string] $Name, [object[]] $Stages)
    $path = Join-Path $Dir $Name
    $doc = [ordered]@{
        schemaVersion = 'winmint.servicing.stages/v1'
        stages        = @($Stages)
    }
    ($doc | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Assert-PinThrows {
    param([scriptblock] $Body, [string] $Label)
    try {
        $null = & $Body
    }
    catch {
        $msg = [string]$_.Exception.Message
        if ($msg -notmatch 'packageFamilyNames') {
            throw "$Label threw an unexpected error: $msg"
        }
        return
    }
    throw "$Label must throw"
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('winmint-appx-pins-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $absentPath = New-StagesFile $root 'absent.json' @(
        [ordered]@{ opcode = 'MountInstallWim'; parameters = [ordered]@{} }
    )
    $absent = Get-WinMintDebloatPinsFromStages -StagesPath $absentPath
    $absentAppx = @($absent.PinnedRemoveAppx)
    if ($absentAppx.Count -ne 0) {
        throw "absent RemoveProvisionedAppx must yield an empty appx pin list, got $($absentAppx.Count)"
    }
    Assert-WinMintPinnedRemoveDigests -DigestMap @{} -PinnedRemoveAppx $absentAppx

    $capMiss = Join-Path $root 'missing-capability-names.json'
    $featBlank = '   '
    $otherPath = New-StagesFile $root 'other.json' @(
        [ordered]@{
            opcode     = 'RemoveCapabilities'
            parameters = [ordered]@{ namesPath = $capMiss }
        }
        [ordered]@{
            opcode     = 'DisableOptionalFeatures'
            parameters = [ordered]@{ namesPath = $featBlank }
        }
    )
    $other = Get-WinMintDebloatPinsFromStages -StagesPath $otherPath
    if (@($other.PinnedRemoveAppx).Count -ne 0) { throw 'stages without RemoveProvisionedAppx must leave appx pins empty' }
    if (@($other.PinnedRemoveCapabilities).Count -ne 0) { throw 'missing capability names file must stay an empty pin list' }
    if (@($other.PinnedDisableOptionalFeatures).Count -ne 0) { throw 'blank feature names path must stay an empty pin list' }

    $noParam = New-StagesFile $root 'no-param.json' @(
        [ordered]@{ opcode = 'RemoveProvisionedAppx'; parameters = [ordered]@{} }
    )
    Assert-PinThrows { Get-WinMintDebloatPinsFromStages -StagesPath $noParam } 'missing packageFamilyNamesPath'

    $blank = New-StagesFile $root 'blank.json' @(
        [ordered]@{
            opcode     = 'RemoveProvisionedAppx'
            parameters = [ordered]@{ packageFamilyNamesPath = '   ' }
        }
    )
    Assert-PinThrows { Get-WinMintDebloatPinsFromStages -StagesPath $blank } 'blank packageFamilyNamesPath'

    $missingFile = Join-Path $root 'does-not-exist.json'
    $notFile = New-StagesFile $root 'not-file.json' @(
        [ordered]@{
            opcode     = 'RemoveProvisionedAppx'
            parameters = [ordered]@{ packageFamilyNamesPath = $missingFile }
        }
    )
    Assert-PinThrows { Get-WinMintDebloatPinsFromStages -StagesPath $notFile } 'packageFamilyNamesPath not a file'

    $emptyList = Join-Path $root 'empty-ids.json'
    Set-Content -LiteralPath $emptyList -Encoding utf8 -Value '[]'
    $emptyStage = New-StagesFile $root 'empty-stage.json' @(
        [ordered]@{
            opcode     = 'RemoveProvisionedAppx'
            parameters = [ordered]@{ packageFamilyNamesPath = $emptyList }
        }
    )
    Assert-PinThrows { Get-WinMintDebloatPinsFromStages -StagesPath $emptyStage } 'empty packageFamilyNames list'

    $blankIds = Join-Path $root 'blank-ids.json'
    Set-Content -LiteralPath $blankIds -Encoding utf8 -Value '["", "  "]'
    $blankStage = New-StagesFile $root 'blank-ids-stage.json' @(
        [ordered]@{
            opcode     = 'RemoveProvisionedAppx'
            parameters = [ordered]@{ packageFamilyNamesPath = $blankIds }
        }
    )
    Assert-PinThrows { Get-WinMintDebloatPinsFromStages -StagesPath $blankStage } 'blank-only packageFamilyNames list'

    $twoList = Join-Path $root 'two-ids.json'
    Set-Content -LiteralPath $twoList -Encoding utf8 -Value '["Microsoft.BingNews", "Microsoft.BingWeather"]'
    $twoStage = New-StagesFile $root 'two-stage.json' @(
        [ordered]@{
            opcode     = 'RemoveProvisionedAppx'
            parameters = [ordered]@{ packageFamilyNamesPath = $twoList }
        }
    )
    $two = @(
        (Get-WinMintDebloatPinsFromStages -StagesPath $twoStage).PinnedRemoveAppx |
            ForEach-Object { [string]$_ }
    )
    if ($two.Count -ne 2 -or $two[0] -ne 'Microsoft.BingNews' -or $two[1] -ne 'Microsoft.BingWeather') {
        throw "bound stage must return the two ids, got [$($two -join ', ')]"
    }
    $digestThrew = $false
    try {
        Assert-WinMintPinnedRemoveDigests -DigestMap @{} -PinnedRemoveAppx $two
    }
    catch {
        $digestThrew = $true
        if ([string]$_.Exception.Message -notmatch 'keep-flag digest missing') { throw }
    }
    if (-not $digestThrew) { throw 'present appx ids must still fail the digest assert when digests are empty' }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-DebloatStageAppxPins ok'
exit 0
