# Leftover confidence — research spike (2026-08-05)

**Ticket:** 26 · **Issue:** [#38](https://github.com/yanai-sh/winmint/issues/38)  
**Authority:** [KEEPFLAG](../design/KEEPFLAG.md) · [ADR-005](../decisions/ADR-005-keep-flag-matrix.md) · [ADR-006](../decisions/ADR-006-post-keepflag-sequencing.md)

## Question

Should WinMint ship **confidence-tier leftover cleanup** (post-uninstall junk scan, registry/file heuristics, “VeryGood” auto-delete) as product code?

## Answer

**No — deferred past M1/M2.** Leftover confidence is **out of this product era** ([KEEPFLAG](../design/KEEPFLAG.md) locked table). WinMint keep-flag is **remove-list + evidence digests**, not live uninstaller hygiene.

## What BCU taught us (steal ideas, not the binary)

[BCU research](./2026-08-03-bulk-crap-uninstaller.md) documents:

- **Declarative selection** over inventory — `.bcul` include/exclude filters; exclude wins. WinMint already maps this to **static catalog + Profile remove-list** (no BCU polarity in Profile — [ADR-005](../decisions/ADR-005-keep-flag-matrix.md)).
- **Multi-source catalogs** — registry, MSI, Store, features, startup. WinMint **does not** mirror BCU’s live discovery brain; catalog bounds **legal ids** only; ImageServicing inventories the **mounted image** for evidence.
- **Junk / leftover finders** — `JunkManager` + confidence tiers (`VeryGood`, etc.) after uninstall. This is **live-only**, heuristic, and UI-adjacent — **do not ship**.

**Inference:** Borrow **list + catalog + evidence** patterns; reject **confidence-tier leftover deletion** as a Supervisor concern.

## Primary evidence path (unchanged)

| Layer | Role | Research |
|-------|------|----------|
| **ImageServicing (offline)** | Primary remove — provisioned AppX, capabilities, optional features; digests on `winmint.image.evidence/v1` | [offline DISM](./2026-08-03-offline-dism-remove-apis.md) · [capabilities matrix](./2026-08-04-capabilities-features-matrix.md) |
| **ProvisioningSession (FirstLogon)** | Narrow **safety net** — `PackageManager` remove/deprovision if still provisioned | [AppX rehydrate](./2026-08-03-appx-rehydrate-after-oobe.md) |

Offline DISM + deprovision stamps address **inbox provisioned** registration. FirstLogon catches **still-provisioned** families after OOBE — not a substitute for offline work ([rehydrate note](./2026-08-03-appx-rehydrate-after-oobe.md)).

## CDM / consumer features

Per-user **ContentDeliveryManager** tweaks and consumer Store suggestions are a **FirstLogon / policy-stamp** problem, not an offline provisioned-package miss ([rehydrate § CDM](./2026-08-03-appx-rehydrate-after-oobe.md)). Pro smoke SKU limits official CSP support.

**Recommendation:** Do **not** adopt CDM-as-primary keep-flag control until ticket **27** / [ADR-007](../decisions/ADR-007-cdm-not-primary.md) — optional hive stamp only; not the M1/M2 control plane.

## Explicitly out

- Shipping BCU or porting `JunkManager` / `UninstallerAutomatizer`
- Profile **presets** or schema **`v2`**
- Product-default **recommended remove-list**
- Confidence-tier leftover cleanup as deferred ticket material

## Review trigger

Microsoft changes offline provisioned-AppX semantics; maintainer hardware (M4) proves repeated rehydrate on pinned ids despite offline + safety-net; or a future era explicitly rescopes “leftover confidence” with new ADR.
