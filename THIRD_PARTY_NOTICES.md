# Third-Party Notices

WinMint is licensed under GPL-3.0-only. Bundled third-party assets keep
their original licenses.

## Cursor Themes

### Windows 11 Modern Light

- Source: `assets/runtime/cursors/Windows11ModernLight`
- License: See upstream cursor pack distribution.
- Packaged files: `assets/runtime/cursors/Windows11ModernLight/`
- Notes: Windows 11 Modern Light is bundled as the fixed WinMint cursor scheme for the
  default user profile in generated ISOs.

## Font Assets

### Cascadia Code Nerd Font

- Source: https://github.com/microsoft/cascadia-code
- License: SIL Open Font License 1.1
- Packaged files: `assets/runtime/fonts/CascadiaCodeNF-Regular.ttf`
- Notes: The Nerd Font variant is distributed by the upstream Cascadia Code
  release package and is installed system-wide into generated ISOs.

GPL-3.0 for WinMint does not relicense bundled font files.

## Icon Assets

### Simple Icons

- Source: https://simpleicons.org/ and https://github.com/simple-icons/simple-icons
- License: CC0 1.0 Universal
- Packaged files: `assets/ui/wsl/*.svg`, `assets/ui/editors/*.svg`
- Notes: Product marks are used only as visual identifiers. Trademark rights
  remain with their respective owners.

## UI Framework

### WPF UI

- Source: https://github.com/lepoco/wpfui
- Package: https://www.nuget.org/packages/WPF-UI
- License: MIT
- Packaged files: `vendor/wpf-ui/4.3.0/net8.0-windows7.0/`
- Notes: Used as the WPF-native Fluent resource and control foundation for
  the WinMint wizard shell.
