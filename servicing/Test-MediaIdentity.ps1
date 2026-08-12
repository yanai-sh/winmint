#requires -Version 7.6

function Test-WinMintSelectedImage {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $ExpectedIdentity
    )

    if ([int]$Snapshot.IndexCount -ne 1) { return $false }
    if ([string]$Snapshot.Name -cne [string]$ExpectedIdentity.imageName) { return $false }
    if ([string]$Snapshot.Architecture -ine [string]$ExpectedIdentity.architecture) { return $false }
    if ([string]$Snapshot.Edition -ine [string]$ExpectedIdentity.edition) { return $false }
    if ([string]$Snapshot.Build -cne [string]$ExpectedIdentity.build) { return $false }
    return $true
}

function Test-WinMintMediaIdentity {
    param(
        [Parameter(Mandatory)] [string] $MarkerPath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $ExpectedIdentity,
        [Parameter(Mandatory)] $Snapshot
    )

    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) { return $false }
    try {
        $identity = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($identity.schemaVersion -cne 'winmint.media-identity/v1' -or
            $identity.sourceIsoSha256 -cne $ExpectedIdentity.sourceIsoSha256 -or
            [int]$identity.wimIndex -ne [int]$ExpectedIdentity.wimIndex -or
            $identity.imageName -cne $ExpectedIdentity.imageName -or
            $identity.architecture -ine $ExpectedIdentity.architecture -or
            $identity.build -cne $ExpectedIdentity.build) {
            return $false
        }
    }
    catch {
        return $false
    }

    return Test-WinMintSelectedImage -Snapshot $Snapshot -ExpectedIdentity $ExpectedIdentity
}

function Write-WinMintMediaIdentity {
    param(
        [Parameter(Mandatory)] [string] $MarkerPath,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $ExpectedIdentity
    )

    $document = [ordered]@{
        schemaVersion = 'winmint.media-identity/v1'
        sourceIsoSha256 = $ExpectedIdentity.sourceIsoSha256
        wimIndex = [int]$ExpectedIdentity.wimIndex
        imageName = $ExpectedIdentity.imageName
        architecture = $ExpectedIdentity.architecture
        build = $ExpectedIdentity.build
    }
    $temporary = "$MarkerPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $document | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $MarkerPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}
