# Repository structure

Canonical layout. Naming rules: [NAMING.md](NAMING.md). Style: [ARCHITECTURE.md](ARCHITECTURE.md).

Legend: **scaffold** (in day-one seed, often empty/stub) · **smoke** (fill in via tickets) · **later**

```
winmint-v2/
├── README.md, LICENSE, AGENTS.md, CLAUDE.md, GEMINI.md, CONTEXT.md
├── global.json
├── Directory.Build.props
├── Directory.Packages.props
├── WinMint.slnx                          # [scaffold] Orchestrator + Cli + Splash + tests
├── Justfile
├── PSScriptAnalyzerSettings.psd1
├── .editorconfig / .gitattributes / .gitignore
├── .github/workflows/ci.yml
│
├── src/
│   ├── WinMint.Orchestrator/             # [scaffold→smoke] library
│   │   ├── Config/ Planning/ Unattend/ Staging/ Servicing/ Json/
│   │   └── WinMint.Orchestrator.csproj
│   ├── WinMint.Cli/                      # [scaffold→smoke] unelevated CLI
│   ├── WinMint.Splash/                   # [scaffold→smoke] Native AOT splash
│   └── WinMint.Wizard/                   # [later] folder + Assets/ only (not in slnx)
│
├── servicing/                            # [scaffold] stub -File entrypoints (exit 2)
│   ├── Mount-IsoStage.ps1 … Export-Iso.ps1
│   └── private/
│
├── payload/
│   ├── payload-manifest.json             # [scaffold] empty entries[]
│   ├── media/                            # [scaffold] brand media present
│   ├── common/ setup/ agent/ splash/     # [scaffold] .gitkeep → [smoke] scripts
│
├── assets/brand/{mark,plate,lockup,readme}/
├── schemas/  config/                     # [scaffold] gravity
├── tests/
│   ├── WinMint.Orchestrator.Tests/       # [scaffold] xunit.v3
│   ├── WinMint.Cli.Tests/
│   ├── payload/  fixtures/
├── tools/
│   ├── analyze-ps.ps1
│   ├── vm/ validation/                   # [scaffold]
│   └── release/                          # [later]
├── docs/
├── output/  dist/                        # gitignored
```

## Context → folders

| Bounded context | Gravity |
|-----------------|--------|
| Authoring | `src/WinMint.Cli`, `src/WinMint.Wizard`, Orchestrator `Config/` |
| Imaging | `src/WinMint.Orchestrator`, `servicing/` |
| Provisioning | `payload/`, `src/WinMint.Splash` |

## Day-one seed vs Smoke fill-in

**In the seed (scaffold):** solution + empty projects, gravity folders, brand, payload media, servicing stubs, docs/ADRs, Just/CI.

**Smoke tickets fill in:** Orchestrator plan/unattend, real servicing kernels, FirstLogon payload, splash host, schemas, VM harness.

**Shelved in companion `future-assets/` zip** (or v1 `docs/v2/future-assets/`): wizard pickers, shell presets, WebView2 reference HTML.

## Anti-patterns

- Clean-Architecture folder theater (`Application/Domain/Infrastructure` per feature) without a second UI
- Wrapping v1 `WinMint.ps1` as one Servicing call
- Root `Assets/` + `assets/` (case collision)
- PascalCase content trees (`Payload/Media/Cursors`) — use lowercase paths
- Committing huge splash/wizard binaries long-term
