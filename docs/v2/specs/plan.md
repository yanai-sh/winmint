# Plan: v2 starter packaging polish → zip

Implements [`2026-07-18-v2-starter-packaging.md`](2026-07-18-v2-starter-packaging.md).

## Locked decisions (this pass)

| Question | Decision |
|----------|----------|
| P1 ceremony | **Yes** — drop stub `README_USAGE.md`; keep thin `GEMINI.md`; keep strict `Directory.Build.props` (scaffold already green) |
| future-assets names | **Modernize now** — flat desktop pickers, `zed.svg`, document SVG gaps |
| Zip output | `docs/v2/dist/` (covered by root `dist/` gitignore) |
| `avatar.bmp` | **Keep** (Windows account-picture BMP slot) |
| Zip now? | After polish + verify; create zips only when checklist green |

## Components / order

1. **Seed docs honesty** — STRUCTURE already updated; sync LAYOUT/PORT/README leftovers; success criteria in packaging spec.
2. **Seed ceremony** — delete `README_USAGE.md`; ensure brand README is sole inventory.
3. **CI realism** — solution exists → keep Just + full gate; analyze-ps stays unconditional.
4. **future-assets** — flatten `ui/desktop/windhawk/`; rename `zedindustries.svg` → `zed.svg`; README gap table; wizard-webview2 README labels dual entrypoints + legacy hero filenames (avoid HTML churn unless trivial).
5. **Verify** — `dotnet build/test` + `analyze-ps` from seed root.
6. **Package** — two zips into `docs/v2/dist/` + listing audit script.

## Risks

| Risk | Mitigation |
|------|------------|
| Stale IDE index shows deleted dual trees | Package from live disk; verify zip listing |
| `Compress-Archive` path quirks on Windows | Zip seed `*` contents vs folder; future-assets keep root folder name |
| Harsh props break later tickets | Leave as-is; tickets own relaxations |

## Parallel vs sequential

- Seed ceremony ∥ future-assets rename
- Verify must follow both
- Zip last

## Checkpoints

- [x] Plan reviewed (this file)
- [x] Polish tasks done ([todo.md](todo.md))
- [x] Verify green (`Verify-StarterPackage.ps1` + build/test/analyze-ps)
- [x] Human OK to zip → produce archives into `docs/v2/dist/` (`20260718-210846`)
