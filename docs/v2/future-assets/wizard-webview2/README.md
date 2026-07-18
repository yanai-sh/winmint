# wizard-webview2/

**Reference only.** Harvest layout/UX ideas for a future Avalonia wizard. Not authority for v2 product UI or the native splash host.

## Entrypoints (do not rename files)

| Files | Role |
|-------|------|
| `index.html` + `app.js` + `styles.css` | Provisioning / setup-shell style UI (fullscreen status surface) |
| `wizard.html` + `wizard.js` + `wizard.css` | Authoring wizard (profile intent UI) |
| `tokens.json` | Shared design tokens used by the HTML/CSS |

Relative paths inside the HTML/JS assume these filenames. Renaming would break refs for no packaging gain — document only.

## Legacy hero rasters

| File | Note |
|------|------|
| `winmint_hero.png` | Legacy v1 splash/hero raster |
| `winmint_hero_ui.png` | Legacy v1 UI-sized hero (`index.html` references this) |

These are **not** the brand authority. Day-one seed splash mark is `assets/brand/mark/splash.png` (see seed `assets/brand/README.md`).
