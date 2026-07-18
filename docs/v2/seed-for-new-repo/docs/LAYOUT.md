# Content layout

Folder casing and roots: **[NAMING.md](NAMING.md)**. Full tree (including day-one `src/` scaffold): **[STRUCTURE.md](STRUCTURE.md)**.

## Split

| Root | Role |
|------|------|
| `assets/brand/` | Shared brand (not ISO-staged) |
| `payload/media/` | ISO-staged media |
| `src/` | Day-one .NET scaffold (`WinMint.Orchestrator` / `Cli` / `Splash`; Wizard placeholder later) |
| `src/WinMint.Wizard/Assets/` | Avalonia-only `AvaloniaResource` (later) |

```
assets/brand/{mark,plate,lockup,readme}/
payload/media/{account,associations,cursors/modern,fonts,terminal,wallpaper}/
payload/{common,setup,agent,splash}/
src/WinMint.{Orchestrator,Cli,Splash}/   # scaffold in seed; Smoke fills behaviour
```

Deferred pickers / shell presets stay on the v1 shelf at `docs/v2/future-assets/` (not copied into the new repo on day one). That shelf uses modernized names (`ui/desktop/windhawk.*`, `zed.svg`); it is not a forever-v1 name freeze.
