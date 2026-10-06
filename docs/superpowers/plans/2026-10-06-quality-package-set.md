# Catalog quality package-set — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package-set module owns LCU resolve + checkpoint/DU **discovery** (membership). `Add-QualityUpdates` acquires via existing `Get-WinMintCatalogPayload` and applies only — no Catalog HTML membership parsing in Add.

**Architecture:** Extract discovery that today lives inline in `Add-QualityUpdates.ps1` (checkpoint KB loop + Dynamic Update Setup/SafeOS search) into `Get-WinMintQualityPackageSet`. Injectable **discovery** adapter (fixture/mock) parallels the existing Acquire adapter from #132. Parsers and acquire helpers stay in `Resolve-WinMintQualityUpdate.ps1`. ADR-013 unchanged.

**Tech Stack:** PowerShell 7.6+ servicing kernels, HTML fixtures under `tests/fixtures/catalog/`, contract `tests/contract/Test-QualityCatalog.ps1`.

## Global Constraints

- Spec: GitHub issue #153
- Package-set wraps LCU resolve + checkpoint/DU discovery; Add does **not** re-parse Catalog HTML for membership
- Reuse `Get-WinMintCatalogPayload` acquire (#132 done) — do not re-shallow / reinvent BITS/cache
- ADR-013 unchanged (`docs/decisions/ADR-013-catalog-lcu.md`)
- Fixture/mock second adapter for **discovery** (inject HTML or pre-built rows) — never live Catalog network inside `just check`
- Out of scope: human LCU slipstream (#123 done) · Prepared media · Gate B / ChipAxis / ProfileDraft · expected-evidence / HostReview
- Prefer discovery-only + fixtures if Primary (#96) wipe is in flight; if DISM apply order / RollupFix / quality digests change, re-prove Gate B before Flash
- Ponytail: one package-set function + thin Add rewrite; do not split Resolve file unless it becomes unreadable
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused contract while iterating; `just check` before final task commit
- Work on branch `sdd/153-quality-package-set`; commit when a task’s Commit step says so
- After land: close #153 with summary

## File map

| File | Responsibility |
|------|----------------|
| `servicing/Get-WinMintQualityPackageSet.ps1` (new) **or** functions appended in `Resolve-WinMintQualityUpdate.ps1` | Prefer **new thin file** that dots Resolve; owns `Get-WinMintQualityPackageSet` |
| `servicing/Resolve-WinMintQualityUpdate.ps1` | Keep parsers, `Invoke-WinMintQualityCatalogResolve`, `Get-WinMintCatalogPayload`, apply/order helpers |
| `servicing/Add-QualityUpdates.ps1` | Package-set → acquire each member → expand SSU → apply; no `Invoke-WinMintCatalogSearchHtml` for membership |
| `tests/contract/Test-QualityCatalog.ps1` | Package-set identities via fixture discovery adapter |
| `tests/fixtures/catalog/` | Reuse existing search/details HTML; add only if a DU/checkpoint identity case needs a new snippet |

**Preferred shape (ponytail):** if a new file is &lt; ~80 lines of glue, create it; otherwise add `Get-WinMintQualityPackageSet` to Resolve and have Add dot Resolve only (already does today via shared path — check how Add loads helpers).

---

### Task 1: `Get-WinMintQualityPackageSet` + identity contract

**Files:**
- Create or extend: package-set function (see file map)
- Modify: `tests/contract/Test-QualityCatalog.ps1`
- Reuse: `tests/fixtures/catalog/search-*.html`, `details-*.html`

**Interfaces:**
- Produces: `Get-WinMintQualityPackageSet` parameters:
  - Mandatory: `Version`, `Architecture`, `ImageUbr` (same as resolve)
  - Optional: `-Discover <scriptblock>` — when omitted, live path uses existing `Invoke-WinMintCatalogSearchHtml` / DetailsHtml (same as today’s Add); when supplied, contract injects fixture HTML / pre-parsed rows **without network**
- Return `[pscustomobject]`:
  - `Skipped` / `Kb` / `UpdateId` / `PackageUbr` / `Title` / `Label` / `Family` / `DetailsHtml` — from LCU resolve (same fields Add uses today)
  - `Checkpoints` — `[object[]]` of `{ Kb, UpdateId, Title }` (membership only; no file paths)
  - `Setup` — `$null` or `{ Kb, UpdateId, Title }`
  - `SafeOs` — `$null` or `{ Kb, UpdateId, Title }`
- When resolve is skipped (image UBR ≥ Catalog): return Skipped=$true and empty Checkpoints/Setup/SafeOs
- Discovery adapter contract: scriptblock receives enough context to return search/details HTML **or** the membership rows; pick the smallest injection that reuses `ConvertFrom-WinMintCatalog*` without duplicating parsers (prefer inject HTML strings keyed by query/kind)

- [ ] **Step 1: Write failing contract** for package-set identities

```powershell
# After existing resolve/acquire tests; dot package-set if separate file
$set = Get-WinMintQualityPackageSet `
    -Version '10.0.26200.8037' `
    -Architecture 'ARM64' `
    -ImageUbr 8037 `
    -Discover {
        param($Context)
        # Return fixture HTML for LCU search, details (with checkpoint KBs), and DU search
        # shaped however Get-WinMintQualityPackageSet documents — must not call live Catalog
    }
if ($set.Skipped) { throw 'Test-QualityCatalog: expected non-skipped package-set for fixture train' }
if ([string]::IsNullOrWhiteSpace($set.Kb) -or [string]::IsNullOrWhiteSpace($set.UpdateId)) {
    throw 'Test-QualityCatalog: package-set missing LCU identity'
}
foreach ($ck in @($set.Checkpoints)) {
    if ([string]::IsNullOrWhiteSpace($ck.Kb) -or [string]::IsNullOrWhiteSpace($ck.UpdateId)) {
        throw "Test-QualityCatalog: checkpoint identity incomplete: $($ck | ConvertTo-Json -Compress)"
    }
}
# If fixture DU search includes Setup/SafeOS for that month/label, assert those identities too;
# if fixture lacks DU rows, Setup/SafeOs may be $null — document which fixtures cover which.
```

Use existing catalog fixtures where possible (`details-kb5121003.html` already exercises checkpoint parsing via `ConvertFrom-WinMintCatalogCheckpointKb`). Extend fixtures only if DU identity cannot be asserted otherwise.

- [ ] **Step 2: Run Test-QualityCatalog — expect FAIL** (function missing)

```powershell
pwsh -NoProfile -File tests/contract/Test-QualityCatalog.ps1
```

- [ ] **Step 3: Implement `Get-WinMintQualityPackageSet`**

Move logic currently in Add L123–158 into the function:
1. Call resolve (live or via Discover-injected search/details HTML into `Resolve-WinMintQualityUpdate`)
2. For each checkpoint KB from `ConvertFrom-WinMintCatalogCheckpointKb`, discover ARM64 row (search HTML via Discover or live)
3. DU Setup + SafeOS via `Select-WinMintDynamicUpdate` on DU search rows
4. Return identities only — **no** `Get-WinMintCatalogPayload` inside package-set

- [ ] **Step 4: Contract green for identities; Commit**

```
feat(servicing): quality package-set discovery (LCU + checkpoint + DU)
```

---

### Task 2: Add = acquire + apply only + gate green

**Files:**
- Modify: `servicing/Add-QualityUpdates.ps1`
- Modify: `tests/contract/Test-QualityCatalog.ps1` if Add is exercised there (mocked apply path)
- Grep: ensure no remaining `Invoke-WinMintCatalogSearchHtml` / `ConvertFrom-WinMintCatalogSearchHtml` **inside Add** for membership (package-set owns those calls)

**Interfaces:**
- Consumes: `Get-WinMintQualityPackageSet` → identities; `Get-WinMintCatalogPayload` per UpdateId; existing expand/apply helpers
- Add flow after WIM snap:
  1. `$set = Get-WinMintQualityPackageSet -Version … -Architecture … -ImageUbr …`
  2. If `$set.Skipped` → same skip evidence path as today
  3. Acquire LCU via `Get-WinMintCatalogPayload -UpdateId $set.UpdateId …`
  4. Expand SSU / boot.stl (unchanged)
  5. Foreach `$set.Checkpoints` → `Get-WinMintCatalogPayload` (no HTML)
  6. If `$set.Setup` / `$set.SafeOs` → acquire only
  7. `Invoke-WinMintQualityPackagesApply` (unchanged leaf order)

- [ ] **Step 1: Failing guard in contract** (source text)

```powershell
$addSrc = Get-Content -LiteralPath (Join-Path $repo 'servicing\Add-QualityUpdates.ps1') -Raw
if ($addSrc -notmatch 'Get-WinMintQualityPackageSet') {
    throw 'Add-QualityUpdates must call Get-WinMintQualityPackageSet'
}
if ($addSrc -match 'Invoke-WinMintCatalogSearchHtml') {
    throw 'Add-QualityUpdates must not call Invoke-WinMintCatalogSearchHtml (package-set owns discovery)'
}
```

- [ ] **Step 2: Rewrite Add** to the acquire+apply flow above; keep progress/output strings useful

- [ ] **Step 3: Run contracts + `just check`**

```powershell
pwsh -NoProfile -File tests/contract/Test-QualityCatalog.ps1
just check
```

Expected: PASS

- [ ] **Step 4: Commit**

```
refactor(servicing): Add-QualityUpdates acquire+apply via package-set
```

- [ ] **Step 5: Close #153** with summary (package-set path; Add no longer parses Catalog HTML for membership). Note Gate B re-prove only if apply/digest behavior changed.

---

## Self-review

1. Spec coverage: package-set wraps resolve+discovery · Add acquire+apply · reuse Get-WinMintCatalogPayload · fixture discovery adapter · ADR-013 untouched · Gate B out of scope — all tasked.
2. Placeholders: Discover scriptblock shape left intentionally flexible in Step 1 with “smallest injection” — implementer must pick one concrete shape in Task 1 Step 3 and update the contract to match (not TBD later).
3. Names: `Get-WinMintQualityPackageSet` consistent across tasks; acquire stays `Get-WinMintCatalogPayload`.
