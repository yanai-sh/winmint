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

Deferred shelf: `docs/v2/future-assets/` (not day-one). Shell presets when layers land; `ui/` pickers are placeholders only (Avalonia not early).
