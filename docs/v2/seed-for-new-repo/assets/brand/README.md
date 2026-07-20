# brand/

Identity pack. Wordmark lives inside lockups (no standalone wordmark file).

| Path | Role |
|------|------|
| `mark/color.svg` | Canonical full-color vector mark |
| `mark/white.svg` / `mark/mono.svg` | White / `currentColor` mark |
| `mark/master.png` | High-res mark raster (2508²) |
| `mark/splash.png` | Splash host mark (256²) |
| `mark/ui-132.png` / `mark/ui-28.png` | Small UI rasters |
| `plate/mark.png` / `plate/ui-28.png` / `plate/app.ico` | Mark on charcoal squircle plate |
| `lockup/{dark,light,adaptive}.svg` | Mark + **WinMint** wordmark |
| `readme/{dark,light}.svg` | GitHub README lockups |

Root README hero (paths from **repo root**):

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
  <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
</picture>
```

Picker icons (if any) are placeholders under `future-assets/ui/` — not in this seed; Avalonia is not early v2 work.
