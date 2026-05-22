# WinMint

Opinionated Windows 11 ISO builder for clean developer workstation installs.

WinMint starts from the Windows ISO you provide, applies a focused workstation
baseline, stages setup/first-logon automation, and emits a bootable ISO. It does
not ship or pin a hidden golden Windows image.

## Quick Start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-GUI.ps1
```

Remote launcher:

```powershell
irm https://winmint.yanai.sh | iex
```

Headless dry run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 -DryRun
```

## Entry Points

| Entry point | Purpose |
|-------------|---------|
| `WinMint-GUI.ps1` | Primary GPUI launcher |
| `WinMint-CLI.ps1` | Headless/profile-driven build entry |
| `WinMint-LegacyUI.ps1` | Deprecated WPF fallback |
| `winmint.ps1` | Download/verify/launch latest release |

## Requirements

- Windows 11 build host
- PowerShell 7.3+
- Administrator rights for real ISO builds
- Windows 11 25H2+ source ISO
- About 25 GB free scratch space
- `oscdimg.exe` from the Windows ADK, installed manually or through WinMint

## Common Commands

```powershell
# Validate repository syntax and contracts
pwsh -NoProfile -File tools\validation\Validate.ps1

# Smoke-test profile invariants
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1

# Build from an existing profile
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -ProfilePath .\BuildProfile.json

# Create a release bundle
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

## Repository Layout

```text
apps/       GUI front ends: primary GPUI and legacy WPF
src/        Engine, FirstLogon agent, and Windows Setup payloads
tools/      Validation, release, bridge, and authoring tools
tests/      Contract tests and local fixture roots
config/     Product policy and release manifests
schemas/    JSON contracts
assets/     Product assets staged into the image or first-logon flow
docs/       Architecture, distribution, UI, and debloat rationale
```

## Contracts

WinMint has three first-class JSON contracts:

| Contract | Purpose |
|----------|---------|
| `BuildProfile.json` | User/build intent from GUI, CLI, or automation |
| `BuildManifest.json` | Machine-readable record of what the engine did |
| `state.json` | FirstLogon agent retry/resume state |

Schemas live in `schemas/`.

## Product Guardrails

- The user-provided ISO is the serviced Windows source.
- Defender, Firewall, SmartScreen, Windows Update, Store infrastructure,
  WebView2, WSL, IPv6, WinRE, UAC, and the component store stay intact.
- Debloat policy is profile-group based, not a matrix of granular toggles.
- WinMint does not leave behind a recurring maintenance task or background
  drift-fighting service.
- Destructive disk modes are explicit.

## Documentation

- [Project structure](docs/Project-Structure.md)
- [Architecture plan](docs/Architecture-Plan.md)
- [Distribution](docs/Distribution.md)
- [Debloat strategy](docs/Windows-Debloat-Strategy.md)
- [GPUI roadmap](docs/ui_roadmap.md)

## License

WinMint is GPL-3.0-only. See [LICENSE](LICENSE).

Bundled third-party assets retain their original licenses. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
