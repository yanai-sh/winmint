# Security policy

## Supported releases

WinMint is Alpha. Security reports apply to the latest GitHub Release of [yanai-sh/winmint](https://github.com/yanai-sh/winmint) and to `main`. Older tags are not patched.

## How to report

Email **yanai@yanai.sh** with a description, affected tag or commit, and reproduction notes. Do not open a public issue for an unfixed vulnerability. We will acknowledge the report and say when a GitHub Security Advisory is warranted.

## What WinMint does to a machine

ImageServicing mutates a user-supplied Microsoft **Source ISO** offline (elevated `pwsh -File`). The **Output ISO** can install Windows unattended. WinPE **LaunchApply** can erase a discovered non-USB disk. Treat that media as destructive. There is no installed WinMint service and no uninstaller: the host toolkit is a portable folder, and the guest Supervisor erases itself after a green FirstLogon.

## Authenticode and GitHub Releases

GitHub Releases are **explicitly unsigned**. Authenticode is deferred until someone other than the maintainer is expected to run a GitHub Release PE. Do not apply to SignPath Foundation or add a signing workflow until that happens. Do not call a GitHub Release, ZIP, or Output ISO Authenticode-signed.

If that pipeline is ever built:

- **Authenticode** is a timestamped publisher signature on WinMint-owned PE files (and on `.ps1` only if the accepted policy covers scripts).
- The Windows publisher is expected to display **SignPath Foundation** (confirm from the first accepted sample).
- The **Output ISO**, ZIP, JSON, CMD, and Profile files are Digest/hash artifacts, not Authenticode containers. Inner `Supervisor.exe` may carry Authenticode; the ISO file does not.

Free code signing provided by SignPath.io, certificate by SignPath Foundation.

WinMint makes **no SmartScreen or antivirus guarantee**. Authenticode does not mean warning-free, Microsoft-endorsed, or “signed ISO.”

## Manual approval

Every future signing request requires **manual approval** in SignPath. A signing workflow must not publish unsigned artifacts because signing failed.

## Revocation

If a release, certificate, or pipeline is compromised, follow [docs/runbooks/release-signing-incident.md](docs/runbooks/release-signing-incident.md). Bootstrap verification fails closed when revocation status is unavailable. `-Force` does not skip verification.

## Roles

- **Authors / committers / reviewers:** people with write or maintain access, listed by GitHub at [contributors](https://github.com/yanai-sh/winmint/graphs/contributors) and [people](https://github.com/yanai-sh/winmint/settings/access) (the latter is visible to maintainers).
- **Approvers:** the repository owner [yanai-sh](https://github.com/yanai-sh).
