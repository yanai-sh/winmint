# future-assets/

**Deferred shelf for WinMint v2** — not part of the day-one seed commit.

Ship alongside `winmint-v2-seed-*.zip`. Extract next to the new repo (e.g. `../future-assets/`) or keep in the v1 tree at `docs/v2/future-assets/`. Copy pieces **into** the v2 repo only when the matching vertical lands (Avalonia wizard, shell layers).

WinMint **v1** remains a separate reference clone for behaviour harvest (see the seed’s `docs/PORT-FROM-V1.md` once the v2 repo exists). Prefer this shelf over hunting v1 for picker icons and shell presets.

## Inventory

| Path | When | On disk |
|------|------|---------|
| `ui/wsl/` | Wizard distro picker | `ubuntu`, `archlinux`, `fedora`, `nixos` (png+svg); **`pengwin.png` only** (no svg) |
| `ui/editors/` | Wizard editor picker | `cursor`, `neovim` (png+svg); **`vscodium.png` only**; `zed` (png+svg) |
| `ui/desktop/` | Wizard shell-layer picker | Flat `yasb`, `komorebi`, `windhawk` (each png+svg) |
| `shell/windhawk/` | Post-Smoke shell install | `preset.json`, `preset.manifest.json`, `README.md` |
| `shell/yasb/` | Post-Smoke shell install | `config.yaml`, `styles.css`, `preset.manifest.json`, `README.md` |
| `shell/komorebi/` | Post-Smoke shell install | `komorebi.json`, `applications.json`, `whkdrc` |
| `wizard-webview2/` | Reference only | v1 WebView2 HTML/JS/CSS — **not** Avalonia authority; see its README |

## Known gaps

- `ui/wsl/pengwin.svg` — missing (png present)
- `ui/editors/vscodium.svg` — missing (png present)

Do not invent artwork in the packaging pass; fill gaps when the Avalonia wizard vertical lands.

## Intentionally omitted

- BreezeX cursors (product uses seed `payload/media/cursors/modern/` only)
- `img0` / `img100` wallpaper slots (v2 uses `bloom.png` only)
- thide / Nilesoft shell presets (not present on this shelf)
- Brand / splash mark / bloom wallpaper (those ship in the **seed** zip)
