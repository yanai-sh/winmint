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
|   |   |-- accountpicture/
|   |   |-- defaultapps/
|   |   |-- wallpaper/
|   |   `-- desktop/
|   |       |-- komorebi/
|   |       |-- windhawk/
|   |       `-- yasb/
|   `-- ui/
|       |-- editors/
|       |-- desktop/
|       `-- wsl/
|-- cloudflare/
|   `-- winmint/
|-- config/
|   |-- build-profiles/
|   |-- packages.json
|   |-- release-manifest.json
|   `-- tweaks.json
|-- docs/
|   |-- Distribution.md
|   |-- Project-Structure.md
|   `-- Windows-Debloat-Strategy.md
|-- schemas/
|-- apps/
|   `-- gui/
|       `-- src/core/          # UI intent/options helpers (formerly crates/winmint-core)
|-- assets/runtime/desktop/    # windhawk/yasb preset.manifest.json + curated config payloads
|-- src/
|   `-- runtime/
|       |-- image/
|       |   `-- Private/
|       |-- firstlogon/
|       `-- setup/
|-- tests/
|   |-- contract/
|   `-- fixtures/
|       |-- drivers/
|       |-- iso/
|-- tools/
|   |-- assets/
|   |-- audit/
|   |-- gui/
|   |-- release/
|   |-- vm/
|   |-- ui-bridge/
|   `-- validation/
|-- WinMint-CLI.ps1
|-- WinMint-GUI.ps1
|-- winmint.ps1
`-- README.md
```

## Folder Ownership

| Folder | Owns | Must not own |
|--------|------|--------------|
| `src/runtime/image/` | Engine, profile contracts, ISO/WIM servicing, reporting APIs | GUI controls, live-user app installs |
| `apps/gui/` | Primary GUI source-selection shell and profile intent | DISM/WIM servicing, registry hive edits |
| `crates/` | Rust contract helpers and small validation/normalization CLIs | Windows servicing, setup orchestration |
| `src/runtime/firstlogon/` | FirstLogon user setup modules and retry state | Offline image servicing, UI wizard state |
| `src/runtime/setup/` | SetupComplete, FirstLogon, DefaultUser, Specialize payloads | Repo validation helpers |
| `tools/audit/` | Output ISO and live-install audit tooling | Product runtime entry points |
| `tools/vm/` | Hyper-V fixtures, guest push helpers, and VM acceptance harnesses | Product runtime entry points |
| `tests/contract/` | Smoke tests and profile invariant tests | Shipped setup payloads |
| `tools/validation/` | Static validation helpers | Product behavior decisions |
| `tools/release/` | Release bundle assembly and publishing helpers | Runtime source code |
| `assets/brand/` | Product mark and editable brand source files | Generated brand tooling |
| `assets/runtime/` | Payloads staged into the image or FirstLogon flow | UI-only previews |
| `assets/ui/` | GUI preview and selection imagery | Setup/runtime configuration |
| `tests/` | Test fixture roots and future test suites | Product runtime or release payloads |
| `tests/fixtures/iso/` | Local ISO/WIM/ESD/SWM media for tests | Checked-in Microsoft payloads |
| `tests/fixtures/drivers/` | Local driver fixture folders, MSI bundles, and ZIPs | Shipped driver assets |

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
- `docs/codebase/`: current-development snapshot docs for agents and maintainers;
  not continuous authoritative product or release documentation.
- `tools/`: developer-only validation, release, bridge, GUI launcher, and
  utility tools.
- `tests/`: contract tests and local fixture roots.
- generated payloads and scratch files: ISO/log files, user driver payloads,
  driver MSI extracts, and cursor PNG intermediates.

## Modularity Pressure

Keep real product logic in the headless PowerShell backend unless there is a
clear reason to keep a typed helper in Rust. GPUI/Rust remains a frontend layer
for intent, previews, and small contract helpers; PowerShell owns DISM, registry
hives, Windows Setup, FirstLogon work, release tooling, validation, and elevation
handoff. New PowerShell files should have a clear runtime reason to exist and
should be grouped under `src/runtime/image`, `src/runtime/setup`,
`src/runtime/firstlogon`, or a developer-only `tools/` owner.
