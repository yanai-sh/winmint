# Third-Party Notices

WinMint is licensed under GPL-2.0-or-later. Bundled third-party assets keep
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

WinMint's GPL-2.0-or-later license does not relicense bundled third-party assets.

## Boot Media Helpers

### UEFI:NTFS

- Source: https://github.com/pbatard/uefi-ntfs
- License: GPL-2.0
- Author: Pete Batard / Rufus project
- Packaged files: None. WinMint downloads and verifies a pinned upstream
  helper image when USB media creation requires it.
- Notes: Used to boot UEFI Windows installation media from an NTFS install
  partition when firmware only provides FAT/FAT32 filesystem support.

## Icon Assets

### Simple Icons

- Source: https://simpleicons.org/ and https://github.com/simple-icons/simple-icons
- License: CC0 1.0 Universal
- Packaged files: `assets/ui/wsl/*.svg`, `assets/ui/editors/*.svg`
- Notes: Product marks are used only as visual identifiers. Trademark rights
  remain with their respective owners.
