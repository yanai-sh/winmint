# Spec: Opinionated shell stack

**Date:** 2026-08-11  
**Plan:** `.cursor/plans/opinionated_shell_stack_065dcc07.plan.md`  
**Authority:** [ADR-009](../../decisions/ADR-009-product-constant-policies.md) · [ADR-011](../../decisions/ADR-011-alpha-posture-and-package-delegation.md) · [DESIGN](../../DESIGN.md)

## Problem Statement

WinMint ships quiet OS posture and MinGit/Nilesoft, but does not stamp a modern PowerShell 7 + Windows Terminal + Starship + scoop CLI toolbox. The product goal is an Omarchy-like curated wipe with limited Wizard choice — not a bring-your-own DSC/`winget configure` workstation.

## Solution

Always-on **shell core** via `ProductPosture` constants:

1. **Winget** (Plan → `winget import`): `Microsoft.PowerShell`, `Microsoft.WindowsTerminal`, `Microsoft.Coreutils` (+ existing MinGit, Nilesoft).
2. **Scoop** (Plan → `scoop.batch`): `starship`, `fzf`, `fd`, `ripgrep`, `bat`, `zoxide`, `jq`, `chezmoi`.
3. **FirstLogon `shell.stamp`** after packages: Cascadia NF fonts; one-shot skel (`$PROFILE`, `powershell.config.json`, `starship.toml`, WT `settings.json` if missing); light chezmoi seed + apply once.

Keep `winget import` (not `winget configure`) as the winget batch API. No Profile redesign. FU-durable quiet expansion is out of scope.

## Product locks

| Lock | Value |
|------|--------|
| Choice model | Shell core product-constant; Wizard chips for personal apps only |
| Channels | winget = Windows apps; scoop = CLI toolbox |
| Prompt | Starship (not Oh My Posh) |
| Skel | One-shot write-if-missing; never re-apply |
| Chezmoi | Scaffold basic templates only; no secrets / git identity |
| Orchestration | BuildPlan + Supervisor; not Autopilot / PPKG / Intune / configure-as-brain |

## Job order (FirstLogon packages phase)

Existing product jobs → winget import / scoop.batch → **`shell.stamp`** → (WSL as today).

`shell.stamp` is best-effort like other packages unless `--package-strict`.

## Skel paths

| Asset | Target |
|-------|--------|
| Profile | `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |
| PS config | `%USERPROFILE%\Documents\PowerShell\powershell.config.json` |
| Starship | `%USERPROFILE%\Documents\PowerShell\starship.toml` (+ `STARSHIP_CONFIG` in profile) |
| WT | Store or unpackaged `settings.json` — write only if missing / first-boot marker |
| Fonts | Per-user Cascadia Code NF + Cascadia Mono NF |

## Non-goals

- `winget configure` as default
- Autopilot / PPKG / Intune
- Profile `packages.wingetConfigure` path pointers
- Oh My Posh, Terminal-Icons, eza (no Windows ARM64 binary)
- Inside-WSL Comfort bootstrap
- FU-durable quiet policy expansion (separate track)

## Testing

- Plan: merged winget/scoop constants; `shell.stamp` after packages; assets staged.
- ProvisioningSession fakes: stamp skips overwrite; chezmoi seed best-effort.
- `just check` green.

## Tickets

Implement in-repo per plan; no separate issue required for alpha maintainer cut.
