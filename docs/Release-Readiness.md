# Release Readiness

WinMint is ready for broader public use only when the release path is proven, not
just when the app builds locally.

The public launch path is:

```powershell
irm https://winmint.yanai.sh | iex
```

This path must remain ephemeral. It downloads the release zip and `.sha256` into
a unique temp session, verifies SHA256 before extraction, launches the packaged
GUI or CLI from that session, waits for exit, then removes the session. It must
not create a default `%LOCALAPPDATA%\WinMint\versions` install/cache.

## Required Gates

Before publishing a broader-use release:

- Run `pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1`.
- Run `pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer`.
- Run `pwsh -NoProfile -File tools\validation\Validate.ps1 -RunReleaseSmoke`.
- Confirm the release workflow builds `WinMint-<version>.zip` and the matching `.sha256`.
- Confirm `tools\release\Test-WinMintReleaseLaunch.ps1` passes against the built bundle.
- Confirm README and `docs\Distribution.md` still describe the same public launch path and host requirements.

## Not Ready If

Do not treat a release as public-ready if:

- the release zip has no matching `.sha256`
- the default bootstrap path leaves a durable release cache
- the packaged GPUI executable is missing
- the bundle contains tests, tools, generated output, temp files, ISO/WIM/VHD artifacts, or logs
- bootstrap failures do not explain the operation, failure kind, recovery path, and retry safety
- the README, distribution doc, release manifest, and validation tooling disagree

The machine-readable source for this checklist is
`config/release-readiness.json`.
