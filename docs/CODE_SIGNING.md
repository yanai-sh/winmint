# Code signing policy

Free code signing provided by SignPath.io, certificate by SignPath Foundation.

## Status

Current GitHub Releases are **unsigned**. Authenticode is deferred: there is no publisher-trust problem until someone other than the maintainer is expected to run a GitHub Release PE. Do not apply to SignPath Foundation, install the SignPath GitHub App, or add a signing workflow until that happens.

Do not describe GitHub Releases as Authenticode, signed, or a signed Release. **Release** in WinMint is an image-quality Lane (`Test` | `Release`), not a GitHub artifact class. A GitHub Release is the toolkit drop.

If Authenticode is ever enabled, SignPath Foundation remains the preferred route. Authenticode would then be a timestamped publisher signature on WinMint-owned PE files, and on `.ps1` only if the accepted artifact policy covers scripts. The publisher is the certificate holder (**SignPath Foundation**), not the WinMint product name, the maintainer, or Microsoft.

The Output ISO is a Digest. It is never Authenticode-signed as a container. Calling it a signed ISO is false.

## Manual approval

Signing requests require manual SignPath approval. A signing job that cannot verify required artifacts must fail closed and must not publish an unsigned GitHub Release from that workflow.

## Artifact classes

| Class | What | Trust |
| --- | --- | --- |
| WinMint PE | `WinMint.Cli.exe`, `WinMint.Wizard.exe`, `WinMint.Provisioning.exe` / `Supervisor.exe`, `WinMintApply.exe`, `WinMint.*.dll` built from this repo | Authenticode candidate |
| WinMint PowerShell | repo-owned `.ps1` in the toolkit | Authenticode only if SignPath confirms `.ps1` |
| Upstream PE | .NET runtime, Avalonia, WinGet-adjacent, ADK, NuGet | preserve bytes; never re-sign |
| Hash-only | ZIP, `.sha256`, Output ISO, JSON, CMD, Profile, Justfile, docs | Digest only |

## Roles

- Authors / committers / reviewers: [contributors](https://github.com/yanai-sh/winmint/graphs/contributors)
- Approvers: [yanai-sh](https://github.com/yanai-sh)

## Operator warnings

Elevated ImageServicing mutates the Source ISO. WinPE LaunchApply can erase a disk. The toolkit is portable (delete the folder). The guest Supervisor erases itself. There is no Add/Remove Programs uninstaller.

## Revocation

See [SECURITY.md](../SECURITY.md) and [the incident runbook](runbooks/release-signing-incident.md). Unreachable revocation status fails closed.

## What Authenticode does not mean

No SmartScreen/antivirus guarantee. No Microsoft endorsement. No signed ISO. No EV reputation shortcut.
