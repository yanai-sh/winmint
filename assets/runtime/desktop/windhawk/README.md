# Windhawk Preset

`preset.json` is the version-controlled WinMint Windhawk desktop preset.

The preset stores:

- Windhawk mod ids
- pinned mod versions
- include/exclude targets
- architecture metadata
- mod settings

It does not store compiled Windhawk mod DLLs or local Windhawk `ProgramData` state.
During first logon, `src/setup/WindhawkBootstrap.ps1` installs Windhawk through the
agent package manifest, downloads official mod source and precompiled DLLs from
`mods.windhawk.net`, writes the Windhawk registry configuration, and restarts
Windhawk/Explorer.

This runs after the normal Windows OOBE network page. The ISO intentionally does
not bypass that Wi-Fi prompt because online FirstLogon automation depends on it.

Current preset mods:

- `taskbar-auto-hide-speed`
- `taskbar-auto-hide-when-maximized`
- `taskbar-button-click`
- `taskbar-dock-animation`
- `taskbar-icon-size`
- `taskbar-tray-show-on-hover`
- `windows-11-taskbar-styler`

To refresh this file, export the current Windhawk registry settings locally, then
replace `preset.json`. The export helper is intentionally not part of the app.
