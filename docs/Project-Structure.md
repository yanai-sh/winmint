# WinMint Project Structure

This document defines the target repository architecture. It is intentionally
practical: every folder should tell a maintainer whether a file is product
runtime, setup payload, validation tooling, release infrastructure, or local
fixture.

## Design Rules

- `src/` contains shipped runtime code only.
- `scripts/` contains repo automation and Windows Setup payload scripts. Move it
  gradually toward role-based subfolders without breaking documented commands.
- `config/` contains product policy and repo manifests, not generated state.
- `schemas/` contains public JSON contracts.
- `assets/` contains source-controlled payloads and visual assets required by
  the product posture.
- `cloudflare/` contains deployment source for the bootstrap alias, not WinWS
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
|-- scripts/
|   |-- audit/
|   |-- release/
|   |-- setup/
|   |-- test/
|   |-- ui-automation/
|   `-- validation/
|-- src/
|   |-- WinWS/
|   |-- WinWS.Agent/
|   `-- WinWS.UI/
|-- tests/
|   `-- fixtures/
|       |-- drivers/
|       |-- iso/
|       `-- uupdump/
|-- vendor/
|-- WinMint-CLI.ps1
|-- WinMint-UI.ps1
|-- winmint.ps1
`-- README.md
```

## Folder Ownership

| Folder | Owns | Must not own |
|--------|------|--------------|
| `src/WinWS/` | Engine, profile contracts, ISO/WIM servicing, reporting APIs | WPF controls, live-user app installs |
| `src/WinWS.UI/` | PowerShell WPF wizard, UI state, previews, profile creation | DISM/WIM servicing, registry hive edits |
| `src/WinWS.Agent/` | FirstLogon user setup modules and retry state | Offline image servicing, UI wizard state |
| `scripts/setup/` | SetupComplete, FirstLogon, DefaultUser, Specialize payloads | Repo validation and UI audit helpers |
| `scripts/audit/` | Output ISO and live-install audit tooling | Product runtime entry points |
| `scripts/ui-automation/` | UIA drivers, fixture capture, visual snapshots | Engine build logic |
| `scripts/test/` | Smoke tests and profile invariant tests | Shipped setup payloads |
| `scripts/Validation/` | Static validation helpers | Product behavior decisions |
| `scripts/release/` | Release bundle assembly and publishing helpers | Runtime source code |
| `tests/` | Test fixture roots and future test suites | Product runtime or release payloads |
| `tests/fixtures/iso/` | Local ISO/WIM/ESD/SWM media for tests and UI audit runs | Checked-in Microsoft payloads |
| `tests/fixtures/drivers/` | Local driver fixture folders, MSI bundles, and ZIPs | Shipped driver assets |
| `tests/fixtures/uupdump/` | Local UUP Dump zips/folders/conversion outputs | Bundled Microsoft payloads |

The script subfolder layout is a migration target. Existing documented root-level
script entry points may remain as thin wrappers until docs, tests, and release
packaging have moved together.

## Release Boundary

`config/release-manifest.json` is the release gate. The bundle script should read
that manifest instead of accumulating hand-written cleanup rules. If a folder is
kept for development but should not ship, exclude it in the manifest and document
why here or in the manifest-adjacent commit.

`scripts\Validation\Modules\Repository.ps1` enforces the low-noise repository
custody checks that are easy to forget: required docs, generated-artifact
tracking, release-manifest roots, pre-commit hook target, and canonical path
casing.

Current non-runtime exclusions:

- `cloudflare/`: service deployment source for `winmint.yanai.sh`.
- `tests/`: local fixture roots and future test suites; executable compatibility
  wrappers may remain under `scripts/test/` during migration.
- generated payloads and scratch files: ISO/log files, driver MSI extracts, cursor
  PNG intermediates.

## Migration Order

1. Split script folders by role while preserving root-level compatibility wrappers.
2. Move validation and test internals out of the release payload once documented
   command wrappers exist.
3. Break oversized runtime files along existing ownership lines:
   UI pages/resources, setup payload generation, headless commands, and FirstLogon
   UI helpers.
4. Revisit vendored dependencies and large assets with a documented offline
   distribution policy.
