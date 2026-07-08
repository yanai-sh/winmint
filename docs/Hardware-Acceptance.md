# Hardware Acceptance

This runbook tracks the real-machine acceptance work that cannot be delegated to
dry runs or Hyper-V. It is maintainer-facing and intentionally calls out checks
that require physical hardware, destructive installs, or release assets.

Physical installs are intentionally deferred until the Hyper-V acceptance path is
credible. Use this document to define the later real-device evidence loop, not as
permission to skip VM validation.

The machine-readable inventory is `config/hardware-acceptance.json`. Keep this
runbook, the inventory, and the tracked build profiles in sync.

## Hardware Roles

| Machine | Role | Notes |
|---------|------|-------|
| Surface Laptop 7 ARM64/aarch64 Snapdragon X Elite Copilot+ PC | Primary development, ARM64 acceptance, Copilot+ validation, physical Copilot-key validation | Prove the ARM64 path first. Use `SurfaceCatalog` with `surface-laptop-7`. Keep Windhawk out until baseline performance is known. |
| ThinkPad amd64/x64 work laptop | Temporary destructive acceptance target before return around June 30, 2026 | Not Copilot+. Should feel like vanilla Windows 11 after install. Use first for time-boxed x64 acceptance. |
| Alienware Aurora amd64/x64 desktop | Long-lived x64 regression and build machine | Gaming-focused. Not Copilot+. Use after ARM64 is proven and ThinkPad coverage is complete. |

## Tracked Profiles

| Profile | Intent |
|---------|--------|
| `config/build-profiles/surface-laptop-7-arm64.json` | ARM64 Surface bare-metal profile: `SurfaceCatalog` / `surface-laptop-7`, keep Edge, Cursor + Zen, Fedora WSL, live install audit, no shell layers or launcher. |
| `config/build-profiles/thinkpad-return-amd64.json` | Keep Edge, no extra browsers, editors, launcher, or shell layers; WSL Ubuntu; `AutoWipeDisk0`. |
| `config/build-profiles/alienware-aurora-amd64.json` | Helium and Zen browsers, Neovim and Zed, Nilesoft, no launcher, Xbox apps removed, manual disk mode. |

## Local Preflight

Run these from the repository root before real-machine installs. Do this only
after the VM acceptance path has already passed for the same build class:

```powershell
pwsh -NoProfile -File tools\validation\Validate.ps1
pwsh -NoProfile -File tools\dev\Invoke-WinMintPesterContract.ps1
```

Validate the tracked profiles from an elevated PowerShell session. If the
session is not already elevated, add `-AllowElevate` to let the CLI show an
explicit UAC prompt:

```powershell
pwsh -NoProfile -File WinMint-CLI.ps1 validate config\build-profiles\surface-laptop-7-arm64.json
pwsh -NoProfile -File WinMint-CLI.ps1 validate config\build-profiles\thinkpad-return-amd64.json
pwsh -NoProfile -File WinMint-CLI.ps1 validate config\build-profiles\alienware-aurora-amd64.json
```

Dry-run each profile before burning media or writing USB. `build -DryRun` also
requires an elevated PowerShell session or `-AllowElevate`:

```powershell
pwsh -NoProfile -File WinMint-CLI.ps1 build config\build-profiles\surface-laptop-7-arm64.json -DryRun
pwsh -NoProfile -File WinMint-CLI.ps1 build config\build-profiles\thinkpad-return-amd64.json -DryRun
pwsh -NoProfile -File WinMint-CLI.ps1 build config\build-profiles\alienware-aurora-amd64.json -DryRun
```

## Surface ARM64 Acceptance

After VM acceptance is credible, use the Surface Laptop 7 as the first physical
acceptance target with `surface-laptop-7-arm64.json`. Build from an elevated
session on the SL7 **before** wiping disk 0 (`AutoWipeDisk0`):

```powershell
pwsh -NoProfile -File tools\dev\Build-WinMintSl7BaremetalElevated.ps1
```

Confirm:

- FirstLogon completes and can resume cleanly after interruption or reboot.
- The build profile selects `SurfaceCatalog` with `surface-laptop-7` (catalog-only; no host export).
- `WinMint-DriverInventory.json` reports the included offline-safe Surface
  driver subset and the excluded/deferred firmware-class drivers.
- Debloated Edge is present (`keep.edge`), Zen Browser and Cursor install at FirstLogon.
- Fedora WSL distro selection completes.
- Live install audit reports zero errors.
- Standard Windows desktop starts (no YASB, Raycast, or other shell layers).
- Game Mode and HAGS baseline registry stamps are present.
- Physical Copilot key opens Windows Search (no launcher installed).

## Release And Bootstrap

After profile acceptance is credible, verify the release path without inventing
or assuming a version:

```powershell
$Version = Read-Host 'Release version'
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version $Version
```

Confirm `dist\` contains the release zip and matching `.sha256` file. The
bootstrap path must refuse a release when the expected hash asset is missing or
does not match. Smoke-test `winmint.ps1` and the Cloudflare alias path at a high
level by confirming they fetch the intended release, verify the hash, run from a
temporary session, remove that session afterward, and launch the packaged entry
point.

The release readiness gates live in `docs\Release-Readiness.md` and
`config\release-readiness.json`.

## Live Install Audit

Live install audit is enabled on the SL7 bare-metal profile
(`features.liveInstallAudit: true`). FirstLogon runs the staged copy at
`C:\Windows\Setup\Scripts\Audit-LiveInstall.ps1` and writes
`C:\ProgramData\WinMint\Logs\LiveInstallAudit.json`. For manual reruns from the
repo:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\audit\Audit-LiveInstall.ps1 `
  -SetupProfilePath C:\Windows\Setup\Scripts\WinMintSetupProfile.json `
  -OutputPath C:\ProgramData\WinMint\Logs\LiveInstallAudit.json `
  -IncludeInventory
```

Treat audit findings as signals, not acceptance blockers by themselves. Convert
real product issues into contract tests, setup fixes, or FirstLogon fixes.

## Evidence Loop

After each real hardware install, copy evidence with:

```powershell
pwsh -NoProfile -File tools\dev\Collect-WinMintHardwareEvidence.ps1 `
  -MachineId surface-laptop-7-arm64 `
  -OutputDir output\hardware-evidence\sl7-2026-07-07
```

The collector copies the standard artifact set from the installed system and the
latest host build output, then writes `acceptance-result.json` (see
`schemas/winmint.acceptanceresult.schema.json`) plus a `notes.md` stub. Do not
start this loop until VM acceptance has passed for the same build class. Keep one
folder per machine and date under a local, ignored output path such as
`output\hardware-evidence\<machine>-<date>`.

Collect these when available:

- `BuildProfile.json`
- `BuildManifest.json`
- `BuildDelta.json`
- `WinMint-DriverInventory.json` when drivers were selected
- `C:\Windows\Setup\Scripts\WinMintSetupProfile.json`
- `%LOCALAPPDATA%\WinMint\state.json`
- `C:\ProgramData\WinMint\Logs`
- `LiveInstallAudit.json` when audit was enabled or run manually

Add a short `notes.md` beside the copied artifacts with:

- machine id from `config/hardware-acceptance.json`
- source ISO name and architecture
- install date
- whether FirstLogon completed without retry
- hardware-only observations such as Wi-Fi, keyboard/trackpad, Copilot key,
  sleep/resume, display scaling, and shell-layer startup
- any issue that should become a contract test or product fix

Do not automate this further until at least one Surface Laptop 7 run and one x64
run show which parts are repetitive or error-prone.

## x64 Follow-Up

Stabilize amd64/x64 only after the ARM64 path is proven. Use the ThinkPad first
because the install is destructive and time-boxed before return around
June 30, 2026. Use the Alienware Aurora later for long-term x64 regression and
build loops.

Review this runbook around June 30, 2026. If the ThinkPad has already been
returned or the deadline changed, remove or update the temporary ThinkPad
acceptance target before relying on this plan.
