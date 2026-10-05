# ADR-015: Desktop surfaces have two independent axes

## Decision

The desktop model has two independent choices:

- **Taskbar surface:** the Windows taskbar (the default) or YASB + tHide.
- **Window management:** Komorebi is an independent optional choice.

The wizard keeps these choices in the Software stage. The package catalog
owns the package IDs. The desktop provisioning job owns tHide installation,
including its pin and hash verification. Nilesoft Shell remains an included
WinMint component for Windows-cohesive shell chrome, not a user selectable
taskbar layer. Komorebi's personal-use/workplace-commercial licensing warning
is shown wherever it is selected.

## Why

Taskbar presentation and window management solve different problems. Modeling
them separately makes the Windows default explicit, permits YASB without
implying a window manager, and lets Komorebi be enabled without changing the
taskbar surface. Package selection carries this intent while preserving
`winmint.profile/v1`.

## Rejected

- Flat package checkboxes, which hide the taskbar/window-management distinction.
- Overlapping taskbar layers, which make ownership of the desktop surface
  ambiguous.
- Curated Windhawk automation until it has a stable CLI contract.
- Redistribution of cursors without a license.
