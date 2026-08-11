# Spec: Packages proof (catalog-time source validity)

**Date:** 2026-08-11  
**Authority:** [ADR-010](../../decisions/ADR-010-arm64-package-policy.md) · [ADR-011](../../decisions/ADR-011-alpha-posture-and-package-delegation.md) · [package catalog](../../specs/2026-08-05-package-catalog-arm64.md) · [TDD](../../TDD.md)

## Problem

`just check` never talks to winget/scoop. Catalog rows are shape-checked only. Today’s `just packages-check` proves **exists + arch** (`winget show` / scoop manifest URL), not installability, and leaves no artifact for offline CI to enforce. A renamed winget id or scoop arm64 URL drift can ship until Smoke/metal.

## Goal

WinMint never ships a **live** winget/scoop install id that has not been proven installable for the target architecture (default **arm64**).

## Invariant

| Gate | Network | Rule |
|------|---------|------|
| `just packages-check` | Yes | Prove every required id; on success write `config/packages.proof.json` |
| `just check` | No | Fail closed if the receipt is missing, stale, or incomplete |

Content-hash freshness only — no time-based expiry. Re-prove when the prove set changes.

## Prove set

Union of:

1. Every `config/packages.json` tool with `stub` ≠ true that lists the target arch in `architectures`
2. Every `ProductPosture` winget and scoop constant id

Rules:

- Product constants **must** appear as non-stub catalog rows (missing → prove fails)
- `stub: true` rows are **skipped** (tentative / future only; not part of live Plan/Wizard product paths)
- `store` (and any non-winget/scoop source): skip for v1 of this gate
- Default prove architecture: `arm64`

## Proof bar (mandatory — not opt-in)

| Source | Method | Receipt `method` |
|--------|--------|------------------|
| winget | `winget install --id <id> --exact --architecture <arch> --dry-run` (refresh sources as needed) | `winget-install-dry-run` |
| scoop | Fetch bucket manifest; require arm64/aarch64 or universal `url`; **download** archive to a temp dir (do not install into the user Scoop root) | `scoop-manifest-download` |

Host requirements: native ARM64 Windows host with App Installer (`winget` on PATH) and network. Wrong arch / missing winget → hard fail.

## Receipt

Committed path: `config/packages.proof.json`

```json
{
  "schema": "winmint.packages.proof/v1",
  "architecture": "arm64",
  "catalogSha256": "<sha256 of packages.json file bytes>",
  "proveSetSha256": "<sha256 of sorted source:id lines in the prove set>",
  "provenAtUtc": "<ISO-8601>",
  "host": { "winget": "<version or path>", "osArch": "ARM64" },
  "entries": [
    { "source": "winget", "id": "Anysphere.Cursor", "method": "winget-install-dry-run" },
    { "source": "scoop", "id": "starship", "method": "scoop-manifest-download", "bucket": "main" }
  ]
}
```

- Stubs omitted from `entries` and from hash inputs
- On prove failure: **do not** overwrite the existing receipt (write temp then atomic replace only on full success)
- Partial success is not a green receipt

## Components

1. **`tools/host/Invoke-PackagesCheck.ps1`** — upgrade from show-only to the proof bar above; emit/replace receipt; keep offline `-SelfCheck` for URI/manifest helper logic
2. **`just packages-check`** — always full prove (remove optional “probe only” as the weak default); still **not** inlined into the `just check` recipe body
3. **Offline unit test** — load catalog + `ProductPosture`; recompute hashes; assert receipt schema, arch, hash match, and every required id present in `entries`; message points at `just packages-check`
4. **Docs** — amend ADR-010 / package catalog notes: catalog-time truth = dry-run prove + receipt, not `winget show` alone

## Maintainer workflow

1. Edit `packages.json` and/or `ProductPosture` package lists
2. On ARM64: `just packages-check` → updates `config/packages.proof.json`
3. Commit catalog + receipt together
4. `just check` green offline on any machine

## Errors

| Case | Behavior |
|------|----------|
| Dry-run / download fails for any id | Exit non-zero; leave prior receipt untouched |
| Transient CDN / source flake | Rerun `just packages-check`; no soft-pass |
| Receipt missing / hash mismatch / missing entry | `just check` fails: run `just packages-check` |
| Stub referenced by live product path | Out of band: keep stubs out of Plan defaults and ProductPosture (catalog stub flag alone is not enough if code selects the id) |

## Non-goals

- Guest FirstLogon install success / `winget import` / `scoop.batch` end-to-end
- Hyper-V prove (escalate later if host dry-run lies; same receipt schema)
- Live winget search in Wizard
- Store source prove
- Network prove inside `just check`
- Time-based receipt expiry
- Proving stub rows

## Testing

- Offline: receipt hash/completeness test in `just check`; script `-SelfCheck` for scoop URI helpers
- Online (maintainer): `just packages-check` against real winget + scoop CDNs on ARM64
- Existing Plan/fake S3 package tests unchanged

## Tickets

Implement in-repo from this spec; amend ADR-010 when landing the receipt gate.
