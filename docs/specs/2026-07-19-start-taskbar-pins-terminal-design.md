# Design: Start/taskbar pins + Windows Terminal profile harden

**Date:** 2026-07-19  
**Status:** Approved for implementation planning  
**Scope:** FirstLogon shell pins (Start + taskbar) for profile editors/browsers; Windows Terminal hard-replace profile list + modern window defaults; mock WSL Terminal profiles for VM smoke.

> Note: `docs/superpowers/` is gitignored in this repo; the canonical tracked copy lives here under `docs/specs/`.

## Problem

1. Profile-selected editors and browsers are Start-pinned today via `ConfigureStartPins`, but **taskbar** only gets Explorer + Terminal from DefaultUser `LayoutModification.xml`. Selected apps never land on the taskbar.
2. Edge pinning rules were unclear; product now requires Start pin when Edge is kept, and taskbar pin only when Edge is the sole browser.
3. Windows Terminal settings **merge** leftover profiles (cmd, duplicates, auto-WSL). Users expect **only** PowerShell 7 (`pwsh -NoLogo`) plus each profile-selected WSL distro (with icon).
4. Offline Terminal seed uses `launchMode: maximized` and opacity 96 — fights “centered windowed” intent.
5. VM smoke with `wslRuntimeValidation=skip` skips real Fedora install, so the Fedora Terminal profile may be missing even though the profile lists the distro.

## Goals

- Always pin **File Explorer** and **Windows Terminal** to Start and taskbar.
- Pin every profile-selected GUI **browser** and **editor** to Start and taskbar (skip CLI-only ids such as `neovim`).
- When Edge is included (`development.browsers` contains `edge`): pin Edge on **Start**; pin Edge on **taskbar** only if it is the **sole** browser (no other ids in `development.browsers`). Edge always remains installed on the image; pinning is not driven by `keep.edge`.
- Hard-replace Terminal `profiles.list` to pwsh + selected WSL distros only.
- Always emit curated WSL Terminal profiles for profile-selected distros; on VM/`skip`, emit the same mock profile (icon + `wsl.exe -d …`) and log that it is mock.
- Terminal window defaults: centered, windowed (`launchMode=default`), One Half Dark, **80% opacity**, Cascadia Code NF, silent bell.

## Non-goals

- Pinning shell layers (Windhawk, YASB, Komorebi, etc.) or arbitrary winget apps outside editors/browsers.
- Guaranteeing WSL launch success for mock profiles on Hyper-V smoke.
- Changing provisioning-lock / splash behavior beyond applying pins after lock release (existing explorer reload path).

## Approach

**Extend FirstLogon shell-pin ownership (recommended).**

| Phase | Owner | Behavior |
|-------|--------|----------|
| Offline / Default user | `DefaultUser.ps1` LayoutModification | Baseline taskbar: Explorer + Terminal only (pre-app install). |
| FirstLogon finish | `FirstLogon.Desktop.ps1` | After agent installs editors/browsers: apply Start pins + taskbar pins from one shared selection policy; rewrite Terminal settings (hard-replace list + defaults). |

Rejected alternatives: build-time-only LayoutModification for profile apps (apps not installed yet); split agent-owned pin module (two writers, race on Edge sole-browser rule).

## Pin policy

### Selection inputs

- `development.browsers` + `development.editors` from agent/setup profile.
- Edge included when `development.browsers` contains `edge`.
- Exclude CLI-only: `neovim` (and any future explicit CLI-only allowlist).

### Start (`ConfigureStartPins`)

Always (in order):

1. File Explorer (`Microsoft.Windows.Explorer`)
2. Settings (`windows.immutablecontrolpanel`)
3. Windows Terminal (`Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`)

Then: each selected browser/editor shortcut (and Edge when kept), resolved via existing Start Menu `.lnk` lookup or exe → created `.lnk` helpers.

### Taskbar

Always (in order):

1. File Explorer
2. Windows Terminal

Then: selected browsers (non-Edge first) → editors.  
**Edge on taskbar only if** Edge is included **and** no other browser ids are selected.

Implementation note: prefer a live-user taskbar pin write that survives explorer reload after provisioning lock release (same timing as today’s Start pin reload). DefaultUser XML remains the first-boot baseline only.

### Failure mode

Missing shortcut/exe → log skip; do not fail FirstLogon plumbing. Policy registry/XML write failure → existing best-effort / error log path.

## Windows Terminal

### Profile list (hard replace)

Every write of `Set-WinMintWindowsTerminalProfiles`:

1. Replace `profiles.list` with **only**:
   - PowerShell: `pwsh.exe -NoLogo`, WinMint GUID `{2c7d8c64-fb18-43d0-9bd0-bf9f6d5c4e22}`, `ms-appx:///ProfileIcons/pwsh.png`
   - One curated entry per profile-selected WSL distro (name, icon, `wsl.exe -d <canonical>`)
2. Keep `disabledProfileSources` for stock dynamic generators (Windows PowerShell, PS Core, Azure, Visual Studio).
3. `defaultProfile` = WinMint pwsh GUID.
4. Call sites (`Set-WinMintFirstLogonWindowsTerminalDefault`, WSL module) must share this helper — no divergent merge path.

### Mock WSL profiles

When profile lists distros and `diagnostics.wslRuntimeValidation = skip` (or equivalent skip path):

- Still emit curated distro profile(s) with real icons/names/command lines.
- Log `terminalProfile=mock` (or equivalent) so smoke evidence can show intent vs install.

### Window / appearance defaults

Force on every rewrite (override sticky Terminal state and fix offline seed drift):

| Setting | Value |
|---------|--------|
| `centerOnLaunch` | `true` |
| `launchMode` | `default` (not maximized / fullscreen / focus) |
| `profiles.defaults.colorScheme` | `One Half Dark` |
| `profiles.defaults.opacity` | `80` |
| `profiles.defaults.font.face` | `Cascadia Code NF` |
| `profiles.defaults.bellStyle` | `none` |

Also update `assets/runtime/windows-terminal/settings.json` (and v2 seed copy if kept in sync) so offline Default-user staging matches: today seed has `launchMode: maximized` and `opacity: 96` — both wrong for this contract. Prefer not restoring a prior maximized layout (`firstWindowPreference` must not defeat centered windowed launch; set to a non-persisted default if needed).

## Acceptance & contracts

1. **Unit/contract:** pin-selection helper — Edge Start yes / taskbar only when sole browser; Terminal+Explorer always; neovim excluded.
2. **Unit/contract:** Terminal hard-replace — list length/shape; defaults opacity 80, `launchMode=default`, `centerOnLaunch`, One Half Dark; mock WSL entry present when skip + distro listed.
3. **Smoke evidence (best-effort):** pulled Terminal `settings.json` matches hard-replace shape for the profile; pin apply logged for selected apps. Do not fail plumbing solely because a pin target shortcut was missing after a failed optional install.

## Files likely touched

- `src/runtime/setup/FirstLogon.Desktop.ps1` — Start + taskbar pin policy
- `src/runtime/setup/WindowsTerminal.Profiles.ps1` — hard replace + defaults
- `assets/runtime/windows-terminal/settings.json` — seed parity
- `src/runtime/setup/DefaultUser.ps1` — keep Explorer+Terminal baseline only
- `tests/contract/*` — pin + Terminal contracts
- Optional: VM inspect/evidence hooks if already reading Terminal settings

## Open implementation detail (non-blocking for plan)

Exact Windows 11 taskbar pin API/XML/registry mechanism for *post-install* pins may need a short spike during implementation; Start path (`ConfigureStartPins`) is already proven. Plan should pick the smallest supported approach that Replace-pins Explorer + Terminal + resolved desktop app links without reintroducing Store/Edge unless Edge sole-browser rule applies.
