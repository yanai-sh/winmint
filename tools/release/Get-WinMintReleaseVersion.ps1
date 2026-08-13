#requires -Version 7.6
Set-StrictMode -Version Latest

function Convert-WinMintReleaseTag {
    param(
        [Parameter(Mandatory)] [string] $Tag,
        [Parameter(Mandatory)] [string] $Commit
    )
    $safe = $Tag.Trim()
    if ($safe -notmatch '^v(\d+)\.(\d+)\.(\d+)$') {
        throw "Tag must match vMAJOR.MINOR.PATCH: $Tag"
    }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    if ($Commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Commit must be a 40-character lowercase SHA-1'
    }
    [pscustomobject]@{
        Tag                  = $safe
        Version              = "$major.$minor.$patch"
        FileVersion          = "$major.$minor.$patch.0"
        AssemblyVersion      = "$major.$minor.0.0"
        InformationalVersion = "$major.$minor.$patch+$Commit"
        RepositoryCommit     = $Commit
    }
}

function Assert-WinMintReleaseWorktree {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Tag
    )
    $status = git -C $RepoRoot status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw 'Release worktree is dirty; commit or stash before packaging.'
    }
    $head = (git -C $RepoRoot rev-parse HEAD).Trim().ToLowerInvariant()
    $tagCommit = git -C $RepoRoot rev-parse --verify --quiet "$Tag^{commit}"
    if ([string]::IsNullOrWhiteSpace($tagCommit)) {
        throw "Tag does not exist at HEAD: $Tag"
    }
    $tagCommit = $tagCommit.Trim().ToLowerInvariant()
    if ($tagCommit -cne $head) {
        throw "Tag $Tag points at $tagCommit, not HEAD $head"
    }
    return $head
}

function Get-WinMintDotnetPublishProperties {
    param([Parameter(Mandatory)] $Version)
    @(
        "-p:Version=$($Version.Version)"
        "-p:VersionPrefix=$($Version.Version)"
        "-p:FileVersion=$($Version.FileVersion)"
        "-p:AssemblyVersion=$($Version.AssemblyVersion)"
        "-p:InformationalVersion=$($Version.InformationalVersion)"
        "-p:RepositoryCommit=$($Version.RepositoryCommit)"
        '-p:Product=WinMint'
        '-p:Company=WinMint contributors'
        '-p:RepositoryUrl=https://github.com/yanai-sh/winmint'
        '-p:PublishRepositoryUrl=true'
    )
}
