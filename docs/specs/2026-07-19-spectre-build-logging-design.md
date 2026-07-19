# Spectre build logging util (engine-only)

**Status:** Approved  
**Date:** 2026-07-19

## Goal

High-fidelity dual-channel ISO build logging: Fluent Spectre chrome on the human console; plain timestamped lines in `WinMint-Build.verbose.log`.

## Scope

- **In:** `src/runtime/image/Private/Console/Logging.ps1` — theme, formatters, `Log*`, section rules, status spinner helper.
- **Out:** FirstLogon agent console rewrite, live tables/charts, new CLI surface.

## Shape

| Layer | Owns |
|-------|------|
| `WinMint.ConsoleTheme.ps1` | Shared One Half Dark palette + line/badge formatters (engine + agent) |
| `Host.ps1` | Spectre import, mute flag, verbose file sinks, `Write-WinMintBuildLog` fan-out |
| `Logging.ps1` | Panels, `Write-WinMintLog`, `Log*`, section rules, status/progress helpers |
| `Display.ps1` `Invoke-Action` | Live UI when allowed; `LogVerbose` start (no duplicate RUN line) |

## Density rules

- Session chrome panel: once per process
- Error: human panel only (no duplicate badge line)
- Live status/progress: no preceding human `Log` line
- WARN stays one-line (no panel) unless explicitly escalated later

## Theme

- Theme: One Half Dark hex (`#61afef` blue accent, `#3e4452` gutter rule, `#98c379` / `#e5c07b` / `#e06c75` levels)
- Level badges: `RUN` / `OK` / `WARN` / `ERR` / `DRY` (markup `on <color>` pills)
- Log lines: colored `│` rail + dim clock + badge
- Session open: `Format-SpectrePanel` Rounded dual-channel chrome
- Errors: Rounded alert panel; `Format-SpectreException` when ErrorRecord
- Summaries: Minimal table inside Rounded panel (`Write-WinMintLogSummaryPanel`)
- Section: `Write-SpectreRule` Center, `WidthPercent 92`
- Status: `Aesthetic` spinner; progress via `Invoke-WinMintSpectreProgress`

## Load order

`Host.ps1` → `Logging.ps1` → `Display.ps1` → `Catalog.ps1` (splash tokens only; console theme lives in Logging).
