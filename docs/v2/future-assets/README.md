# future-assets/

**Deferred shelf for WinMint v2** — not part of the day-one seed commit.

Ship alongside `winmint-v2-seed-*.zip`. Park next to the new repo (e.g. `../future-assets/`) or leave in the v1 tree at `docs/v2/future-assets/`. Do **not** merge into the v2 initial commit.

Avalonia is **not** in WinMint v1 and is **not** an early v2 priority (CLI + Smoke + Payload first). Treat `ui/` as optional placeholders only — do not open tickets to fill SVG gaps or wire pickers until a wizard vertical is actually scheduled.

## Inventory

| Path | Priority | Role |
|------|----------|------|
| `shell/windhawk/` `shell/yasb/` `shell/komorebi/` | Post-Smoke product depth (when shell layers land) | Install presets — useful before any GUI |
| `ui/wsl/` `ui/editors/` `ui/desktop/` | **Placeholder only** | Picker icons for a far-future authoring UI — not Smoke, not near-term |
| `wizard-webview2/` | Reference only | v1 WebView2 HTML/JS — layout/UX archaeology; **not** Avalonia authority |

### Placeholder UI icons (ignore until wizard is scheduled)

| Path | On disk |
|------|---------|
| `ui/wsl/` | `ubuntu`, `archlinux`, `fedora`, `nixos` (png+svg); `pengwin.png` only |
| `ui/editors/` | `cursor`, `neovim` (png+svg); `vscodium.png` only; `zed` (png+svg) |
| `ui/desktop/` | Flat `yasb`, `komorebi`, `windhawk` (each png+svg) |

Known holes (`pengwin.svg`, `vscodium.svg`) are fine to leave empty. Do not invent artwork as busywork.

## Intentionally omitted

- BreezeX cursors (seed uses `payload/media/cursors/modern/` only)
- Extra wallpaper slots (seed uses `bloom.png` only)
- thide / Nilesoft preset trees (Nilesoft is package-install; no shelf content required)
- Brand / splash / bloom / Cascadia NF / modern cursors (those ship in the **seed**)
