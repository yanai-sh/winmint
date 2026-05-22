# WinMint Project Structure

This document defines the target repository architecture. It is intentionally
practical: every folder should tell a maintainer whether a file is product
runtime, setup payload, validation tooling, release infrastructure, or local
fixture.

## Design Rules

- `apps/` contains user-facing application front ends.
- `src/` contains shipped runtime code and staged Windows Setup payloads.
- `tools/` contains repo automation, validation, release, bridge, and utility tools.
- `config/` contains product policy and repo manifests, not generated state.
- `schemas/` contains public JSON contracts.
- `assets/` contains source-controlled product assets split by intent: brand
  identity, runtime payloads staged into the image or FirstLogon flow, and UI
  presentation assets.
- `cloudflare/` contains deployment source for the bootstrap alias, not WinMint
  runtime code.
- `tests/` contains test fixtures and future test suites. Fixture payloads stay
  local and gitignored.
- `output/`, `dist/`, `input/`, ISO/WIM/ESD/SWM/VHD files, logs, and extraction
  scratch directories are generated artifacts.

## Target Topology

```text
.
|-- assets/
|   |-- brand/
|   |-- runtime/
|   |   |-- cursors/
|   |   |-- fonts/
|   |   |-- wallpaper/
|   |   `-- shell/
|   |       |-- komorebi/
|   |       |-- windhawk/
|   |       `-- yasb/
|   `-- ui/
|       |-- editors/
|       |-- shell/
|       `-- wsl/
|-- cloudflare/
|   `-- winmint/
|-- config/
|   |-- build-profiles/
|   |-- packages.json
|   |-- profiles.json
|   |-- release-manifest.json
|   `-- tweaks.json
|-- docs/
|   |-- Distribution.md
|   |-- Project-Structure.md
|   `-- Windows-Debloat-Strategy.md
|-- schemas/
|-- apps/
|   |-- gui/
|   `-- legacy-wpf/
|-- src/
|   |-- engine/
|   |-- agent/
|   `-- setup/
|-- tests/
|   |-- contract/
|   `-- fixtures/
|       |-- drivers/
|       |-- iso/
|       `-- uupdump/
|-- tools/
|   |-- assets/
|   |-- audit/
|   |-- gui/
|   |-- release/
|   |-- ui-bridge/
|   `-- validation/
|-- vendor/
|-- WinMint-CLI.ps1
|-- WinMint-GUI.ps1
|-- WinMint-LegacyUI.ps1
|-- winmint.ps1
`-- README.md
```

## Folder Ownership

| Folder | Owns | Must not own |
|--------|------|--------------|
| `src/engine/` | Engine, profile contracts, ISO/WIM servicing, reporting APIs | WPF controls, live-user app installs |
| `apps/gui/` | Primary GUI source-selection shell and profile intent | DISM/WIM servicing, registry hive edits |
| `apps/legacy-wpf/` | PowerShell WPF wizard, UI state, previews, profile creation | DISM/WIM servicing, registry hive edits |
| `src/agent/` | FirstLogon user setup modules and retry state | Offline image servicing, UI wizard state |
| `src/setup/` | SetupComplete, FirstLogon, DefaultUser, Specialize payloads | Repo validation helpers |
| `tools/audit/` | Output ISO and live-install audit tooling | Product runtime entry points |
| `tests/contract/` | Smoke tests and profile invariant tests | Shipped setup payloads |
| `tools/validation/` | Static validation helpers | Product behavior decisions |
| `tools/release/` | Release bundle assembly and publishing helpers | Runtime source code |
| `assets/brand/` | Product mark and editable brand source files | Generated brand tooling |
| `assets/runtime/` | Payloads staged into the image or FirstLogon flow | UI-only previews |
| `assets/ui/` | GUI preview and selection imagery | Setup/runtime configuration |
| `tests/` | Test fixture roots and future test suites | Product runtime or release payloads |
| `tests/fixtures/iso/` | Local ISO/WIM/ESD/SWM media for tests | Checked-in Microsoft payloads |
| `tests/fixtures/drivers/` | Local driver fixture folders, MSI bundles, and ZIPs | Shipped driver assets |
| `tests/fixtures/uupdump/` | Local UUP Dump zips/folders/conversion outputs | Bundled Microsoft payloads |

Root-level launchers are the public command surface. Product code, staged setup
payloads, and developer tooling live under their owning folders.

## Release Boundary

`config/release-manifest.json` is the release gate. The bundle script should read
that manifest instead of accumulating hand-written cleanup rules. If a folder is
kept for development but should not ship, exclude it in the manifest and document
why here or in the manifest-adjacent commit.

`tools\validation\Modules\Repository.ps1` enforces the low-noise repository
custody checks that are easy to forget: required docs, generated-artifact
tracking, release-manifest roots, pre-commit hook target, and canonical path
casing.

Current non-runtime exclusions:

- `cloudflare/`: service deployment source for `winmint.yanai.sh`.
- `tools/`: developer-only validation, release, bridge, GUI launcher, and
  utility tools.
- `tests/`: contract tests and local fixture roots.
- generated payloads and scratch files: ISO/log files, user driver payloads,
  driver MSI extracts, and cursor PNG intermediates.

## Modularity Pressure

Keep future product logic in Rust when it is not tied to Windows setup APIs.
PowerShell remains the servicing bridge for DISM, registry hives, Windows Setup,
and elevation handoff. New PowerShell files should have a clear runtime reason to
exist and should be grouped under `src/engine`, `src/setup`, `src/agent`, or a
developer-only `tools/` owner.
