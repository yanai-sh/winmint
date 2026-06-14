# WinMint Roadmap

## Planned

### Current customization surfaces

- Fonts: bundled system font options, including Nerd Font payloads.
- Cursor: `Windows 11 Modern`.
- Browsers: `Zen Browser`, `Helium`, `LibreWolf`, `Brave`, and `Edge`.
- WSL distros: `Ubuntu 26.04 LTS`, `Fedora 44`, `Arch Linux`, `NixOS-WSL`, and `Pengwin`.
- Shell layers: the WinMint desktop shell stack remains additive and composable.
- Editors: `Neovim`, `VS Code`, `Cursor`, `Zed`, and `Antigravity`.

### Browser selection

- Add browser install choices to the profile and UI: `Zen Browser`, `Helium`, `LibreWolf`, `Brave`, and `Edge`.
- Make browser selection opt-in. If the user selects nothing, WinMint installs no browser.
- Treat `Edge` as a keep/install choice, so the default subtractive behavior leaves Edge uninstalled unless it is explicitly selected.
- Add a subtle UI warning later when no browser is selected, to reduce accidental no-browser builds without turning the flow into a forced decision.

### WSL distro suggestions

- Keep WSL2 enabled by default, with no distro preinstalled.
- Surface distro suggestions in the UI and profile flow for:
  - `Ubuntu 26.04 LTS`
  - `Fedora 44`
  - `Arch Linux`
  - [`NixOS-WSL`](https://github.com/nix-community/NixOS-WSL)
  - `Pengwin`
- Keep these as suggestions only; the developer still chooses whether to install any distro.

### Editor selection

- Add editor install choices to the profile and UI: `Neovim`, `VS Code`, `Cursor`, `Zed`, and `Antigravity`.
- Keep editors opt-in and leave them unset by default.
- Treat editor selection as independent from browser and WSL choices.

### Linux-like workstation baseline

#### Safe defaults

- Keep the XDG layout as the default for WinMint users:
  - `XDG_CONFIG_HOME=%USERPROFILE%\.config`
  - `XDG_DATA_HOME=%USERPROFILE%\.local\share`
  - `XDG_STATE_HOME=%USERPROFILE%\.local\state`
  - `XDG_CACHE_HOME=%USERPROFILE%\.cache`
  - `XDG_RUNTIME_DIR` as a temp-backed per-user runtime directory
- Keep PowerShell 7 and Windows Terminal as the default shell surface.
- Keep `Windows Terminal` on the taskbar and `Cascadia Code NF` as the default terminal font.
- Keep developer mode, OpenSSH, WSL2, and symlink friendliness enabled by default.
- Treat WinMint as a WSL-first development environment even when no distro is installed yet.
- Keep the Windows-side quality-of-life defaults useful for general daily use, not just for WSL.
- Keep a dotfiles-friendly user layout and prefer user-owned config/state directories over `AppData` when the app supports it.
- Keep user-owned script/shim paths (`~/bin` and `~/.local/bin`) on the user `PATH`.

#### Developer opt-in

- Allow per-folder case sensitivity where the user explicitly wants it.
- Keep a prompt standard like Starship as an opt-in layer for users who want it.
- Keep SSH agent and Git defaults in the developer layer, not the core baseline.

#### Too invasive

- Forcing all apps into a single package ecosystem.
- Globally changing Windows path semantics.
- Replacing native Windows shell behavior with custom wrappers where a supported setting already exists.
- Moving all Windows apps out of `AppData` even when the app does not support XDG or equivalent paths.
