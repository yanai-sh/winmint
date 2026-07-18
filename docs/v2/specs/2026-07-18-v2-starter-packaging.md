# Spec: WinMint v2 starter packaging audit

**Status:** complete — zips in `docs/v2/dist/` (`20260718-210846`, verify exit 0)  
**Scope:** Audit + harden `docs/v2/seed-for-new-repo/` and `docs/v2/future-assets/`, then produce transfer zips.  
**Not in scope:** Smoke product behavior (DMA/DISM/agent logic), creating the GitHub repo, Avalonia Wizard implementation.

## Objective

Ship two intentional, reviewable archives so a new v2 repository can start from a clean greenfield commit, while deferred UI/shell art stays findable without digging through WinMint v1.

**Users:** maintainer transferring the starter; agents opening the new repo.

**Success looks like:** extract seed → README heroes resolve → docs match disk → `WinMint.slnx` restores/builds/tests green → `analyze-ps` runs → no mystery PascalCase trees / duplicate brand files / BreezeX / `img0` → future-assets zip holds every deferred picker + shell preset with a clear README.

## ASSUMPTIONS (locked)

1. **Two archives**, not one flat blob: seed contents for git commit 1; `future-assets/` as a sidecar shelf that stays out of the new repo until those verticals land.
2. **Day-one seed includes the full folder scaffold** — `WinMint.slnx`, `src/WinMint.{Orchestrator,Cli,Splash}`, Wizard placeholder (not in solution), `tests/`, `servicing/` stubs, `tools/{vm,validation,release}`, docs, brand, payload media. Product behavior still arrives via `/to-spec` → tickets.
3. **Brand/media renames already applied** (`mark/`, `plate/`, `lockup/`, `cursors/modern/`, `bloom.png`, `avatar.*`) are the canonical convention; we polish docs/ceremony around them, not rename again unless review finds a better vocabulary.
4. **`avatar.bmp` stays** (Windows account-picture slot often wants BMP).
5. **BreezeX and `img0`/`img100` stay omitted** (product decision).
6. **future-assets picker gaps** (`pengwin.svg`, `vscodium.svg`) are documented as known holes; `zed.svg` is present (renamed from `zedindustries.svg`). Do not invent missing SVGs in this packaging pass.
7. **Zip output location:** `docs/v2/dist/` (covered by root `dist/` gitignore) — not committed into v1.
8. **No third-party installers / ISO / `.scratch` / v1 `output/`** ever enter either zip.
9. **P1 ceremony:** drop stub `README_USAGE.md`; keep thin `GEMINI.md`; keep strict `Directory.Build.props` (scaffold already green).
10. **future-assets names:** modernize now — flat desktop pickers, `zed.svg`, document SVG gaps.
11. **Zips:** create only after polish + verify checklist is green (human OK).

## Tech stack (packaging pass)

| Piece | Choice |
|-------|--------|
| Host | Windows (ARM64-capable maintainer machine) |
| Archives | `Compress-Archive` or `tar -a` → `.zip` |
| Seed root | `docs/v2/seed-for-new-repo/` |
| Shelf | `docs/v2/future-assets/` |
| Spec home | `docs/v2/specs/` (v1 tree; not copied into seed unless desired later) |

## Commands

```powershell
# Inventory (authoritative disk)
Get-ChildItem docs\v2\seed-for-new-repo -Recurse -File | Measure-Object
Get-ChildItem docs\v2\future-assets -Recurse -File | Measure-Object

# Seed gates (must exit 0)
cd docs\v2\seed-for-new-repo
dotnet restore
dotnet build --no-restore
dotnet test --no-build
pwsh -NoProfile -File tools\analyze-ps.ps1

# Package (after polish + human OK — example)
$stamp = Get-Date -Format 'yyyyMMdd'
$out = 'docs\v2\dist'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Compress-Archive -Path (Join-Path $PWD 'docs\v2\seed-for-new-repo\*') `
  -DestinationPath (Join-Path $out "winmint-v2-seed-$stamp.zip") -Force
Compress-Archive -Path (Join-Path $PWD 'docs\v2\future-assets') `
  -DestinationPath (Join-Path $out "winmint-v2-future-assets-$stamp.zip") -Force
```

## Project structure (packaging targets)

```
docs/v2/
  COPY-INTO-NEW-REPO.md          # v1-only instructions
  specs/                         # this spec (+ plans/todo)
  dist/                          # gitignored zip output
  seed-for-new-repo/             # → winmint-v2-seed-*.zip (flat contents = repo root)
    WinMint.slnx, src/, tests/
    assets/brand/{mark,plate,lockup,readme}/
    payload/media/{account,associations,cursors/modern,fonts,terminal,wallpaper}/
    payload/{common,setup,agent,splash}/.gitkeep
    docs/, config/, schemas/, servicing/, tools/
    Justfile, global.json, CI, LICENSE, AGENTS.md, …
  future-assets/                 # → winmint-v2-future-assets-*.zip (keeps folder name)
    ui/{wsl,editors,desktop}/    # flat desktop pickers; modernized editor names
    shell/{windhawk,yasb,komorebi}/
    wizard-webview2/             # reference only (+ README labels)
    README.md
```

### Naming vocabulary (intentional)

| Term | Meaning |
|------|---------|
| `mark` | Leaf/icon only |
| `lockup` | Mark + WinMint wordmark |
| `plate` | Mark on charcoal squircle tile |
| `splash` | 256× mark for native splash host |
| `bloom` | Desktop wallpaper (not the logo) |
| `modern` | Sole cursor pack |
| `shell` | Desktop-layer presets (not `desktop/`) |
| `ui` | Wizard picker art (deferred) |

Lowercase path segments; kebab file names; PascalCase only for future .NET projects.

## Code style (packaging / docs)

- Docs state **what is on disk now** vs **what Smoke will add** — never imply empty folders contain code.
- READMEs use the vocabulary table above; no `winmint_hero_*` leftovers in seed paths.
- Prefer deletion of stub redirects over “see other file” ceremony.
- Zip scripts: PowerShell, `-LiteralPath`, no silent include of parent junk.

Example of honest STRUCTURE snippet:

```markdown
## Day-one (this seed)
WinMint.slnx, src/ scaffold, assets/brand/, payload/media/, docs/, tooling stubs

## Smoke tickets fill in
Orchestrator plan/unattend, real servicing kernels, FirstLogon payload, splash host behaviour, schemas
```

## Testing strategy

| Check | Level | Gate |
|-------|-------|------|
| Disk inventory matches NAMING/LAYOUT | Manual / script | P0 |
| README `<picture>` paths resolve | Manual extract | P0 |
| No forbidden paths in zip listing | Script | P0 |
| `dotnet restore/build/test` + `tools/analyze-ps.ps1` exit 0 | Automated | P0 |
| `just check` documented for seed | Doc | P0 |
| future-assets shelves match README table | Manual | P1 |

No unit-test framework for packaging; one small verify script (optional) that fails if seed still contains `Windows11ModernLight`, `assets/ui`, `img0.jpg`, or `BreezeX`.

## Boundaries

**Always**
- Package from live disk under `docs/v2/{seed-for-new-repo,future-assets}` only.
- Keep `future-assets` out of the new-repo initial commit instructions.
- Update STRUCTURE/LAYOUT/NAMING/PORT-FROM-V1/COPY-INTO-NEW-REPO so they agree with disk before zipping.
- Exclude secrets, ISOs, `EverythingSetup.exe`, `.scratch`, `output/`, `dist/` of v1 product builds.

**Ask first**
- Softening `TreatWarningsAsErrors` / dropping `GEMINI.md` / removing `avatar.bmp` (locked for this pass: keep props + GEMINI + bmp).
- Adding invented SVGs for pengwin/vscodium gaps.
- Committing zips into git (default: **no** — `docs/v2/dist/` gitignored).

**Never**
- Reintroduce BreezeX or Windows theme slot names (`img0`/`img100`) into the seed.
- Nest `future-assets` inside seed for “convenience.”
- Bundle Microsoft Source ISO or claim golden builds.
- Treat `wizard-webview2/` as Avalonia authority.

## Audit findings (baseline 2026-07-18; polish notes)

### Seed — good / done

- Brand role folders + dedupe applied; media kebab paths; modern cursors only; bloom-only wallpaper.
- No `assets/ui` / `payload/desktop` in seed.
- ~91 files / ~9 MB; ADRs + workflow present.
- **STRUCTURE.md honesty** — done: scaffold vs Smoke fill-in vs later.
- **Solution scaffold** — done: `WinMint.slnx` + Orchestrator/Cli/Splash + tests; Wizard placeholder not in slnx.
- **v1 CLAUDE.md path** — points at `docs/v2/COPY-INTO-NEW-REPO.md` (not under seed).
- **P1 ceremony** — `assets/brand/README_USAGE.md` dropped; brand README is sole inventory.

### Seed — deferred (not blocking polish)

- Soften `Directory.Build.props` / drop `GEMINI.md` — locked **keep** for this pass.
- CI winget/Just realism — leave full gate; tickets own relaxations.

### future-assets — polish applied

- Flattened `ui/desktop/windhawk.*` beside yasb/komorebi.
- Renamed `zedindustries.svg` → `zed.svg`.
- README gap table + intentional omissions (BreezeX, img0/img100, thide/nilesoft).
- `wizard-webview2/README.md` labels dual entrypoints + legacy hero filenames.

## Success criteria

- [x] Spec approved (plan.md locked decisions).
- [x] P0 doc/Justfile/CLAUDE fixes applied on disk.
- [x] STRUCTURE / LAYOUT / PORT agree: seed has `src/` scaffold; future-assets is a modernized shelf.
- [x] P1: drop `README_USAGE.md`; brand README sole usage doc.
- [x] future-assets modernized (flat desktop, `zed.svg`, gap docs, wizard-webview2 README).
- [x] Seed verify green: `dotnet restore/build/test` + `analyze-ps` exit 0.
- [ ] `winmint-v2-seed-<date>.zip` extracts to a valid repo root (heroes + LICENSE + AGENTS.md).
- [ ] `winmint-v2-future-assets-<date>.zip` contains `future-assets/{ui,shell,wizard-webview2,README.md}`.
- [ ] Zip listings contain **zero** of: `BreezeX`, `img0`, `img100`, `Windows11ModernLight`, `EverythingSetup`, `.scratch`.
- [x] `COPY-INTO-NEW-REPO.md` still matches the two-zip / seed-only commit story.

## Open questions — resolved

| # | Question | Decision (from plan.md) |
|---|----------|-------------------------|
| 1 | Apply P1 ceremony cuts in this packaging pass, or zip after P0 only? | **Yes** — drop stub `README_USAGE.md`; keep thin `GEMINI.md`; keep strict `Directory.Build.props`. |
| 2 | Modernize future-assets names now, or leave v1 picker names? | **Modernize now** — flat desktop pickers, `zed.svg`, document SVG gaps. |
| 3 | Zip output under `docs/v2/dist/` (gitignored)? | **Confirm** — `docs/v2/dist/` (root `dist/` gitignore covers it). |
| 4 | Keep or drop `avatar.bmp`? | **Keep** (Windows account-picture BMP slot). |
| — | Zip now? | **After** polish + verify; create zips only when checklist green + human OK. |

## Out of scope (next specs)

- Smoke product `/to-spec` (Orchestrator, Servicing, DMA evidence).
- Creating/pushing the GitHub repository.
- Avalonia wizard implementation.
- Zip production (blocked on verify + human OK — see todo.md).

