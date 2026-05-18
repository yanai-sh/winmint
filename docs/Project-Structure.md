# WinMint Project Structure

This document defines the target repository architecture. It is intentionally
practical: every folder should tell a maintainer whether a file is product
runtime, setup payload, validation tooling, release infrastructure, or local
fixture.

## Design Rules

- `apps/` contains user-facing application front ends.
- `src/` contains shipped runtime code and staged Windows Setup payloads.
- `tools/` contains repo automation, validation, release, bridge, and authoring tools.
- `config/` contains product policy and repo manifests, not generated state.
- `schemas/` contains public JSON contracts.
- `assets/` contains source-controlled payloads and visual assets required by
  the product posture.
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
|   |-- cursors/
|   |-- editors/
|   |-- fonts/
|   |-- komorebi/
|   |-- shell/
|   |-- windhawk/
|   |-- wsl/
|   `-- yasb/
|-- cloudflare/
|   `-- winmint/
|-- config/
|   |-- build-profiles/
|   |-- packages.json
|   |-- profiles.json
|   |-- release-manifest.json
|   `-- tweaks.json
|-- docs/
|   |-- Architecture-Plan.md
|   |-- Distribution.md
|   `-- Project-Structure.md
|-- schemas/
|-- apps/
|   |-- WinMint.GPUI/
|   `-- WinMint.LegacyWpf/
|-- src/
|   |-- WinMint/
|   |-- WinMint.Agent/
|   `-- WinMint.Setup/
|-- tests/
|   |-- contract/
|   `-- fixtures/
|       |-- drivers/
|       |-- iso/
|       `-- uupdump/
|-- tools/
|   |-- assets/
|   |-- audit/
|   |-- brand/
|   |-- gpui/
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
| `src/WinMint/` | Engine, profile contracts, ISO/WIM servicing, reporting APIs | WPF controls, live-user app installs |
| `apps/WinMint.GPUI/` | Primary GUI source-selection shell and profile intent | DISM/WIM servicing, registry hive edits |
| `apps/WinMint.LegacyWpf/` | PowerShell WPF wizard, UI state, previews, profile creation | DISM/WIM servicing, registry hive edits |
| `src/WinMint.Agent/` | FirstLogon user setup modules and retry state | Offline image servicing, UI wizard state |
| `src/WinMint.Setup/` | SetupComplete, FirstLogon, DefaultUser, Specialize payloads | Repo validation helpers |
| `tools/audit/` | Output ISO and live-install audit tooling | Product runtime entry points |
| `tests/contract/` | Smoke tests and profile invariant tests | Shipped setup payloads |
| `tools/validation/` | Static validation helpers | Product behavior decisions |
| `tools/release/` | Release bundle assembly and publishing helpers | Runtime source code |
| `tests/` | Test fixture roots and future test suites | Product runtime or release payloads |
| `tests/fixtures/iso/` | Local ISO/WIM/ESD/SWM media for tests | Checked-in Microsoft payloads |
| `tests/fixtures/drivers/` | Local driver fixture folders, MSI bundles, and ZIPs | Shipped driver assets |
| `tests/fixtures/uupdump/` | Local UUP Dump zips/folders/conversion outputs | Bundled Microsoft payloads |

Root-level launchers remain compatibility entry points. Product code, staged
setup payloads, and developer tooling live under their owning folders.

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
- `tools/`: developer-only validation, release, bridge, GPUI launcher, and asset
  authoring tools.
- `tests/`: contract tests and local fixture roots.
- generated payloads and scratch files: ISO/log files, driver MSI extracts, cursor
  PNG intermediates.

## Migration Order

1. Keep root-level compatibility wrappers thin.
2. Move any remaining product decisions out of `tools/` and into `src/`.
3. Break oversized runtime files along existing ownership lines:
   UI pages/resources, setup payload generation, headless commands, and FirstLogon
   UI helpers.
4. Revisit vendored dependencies and large assets with a documented offline
   distribution policy.
