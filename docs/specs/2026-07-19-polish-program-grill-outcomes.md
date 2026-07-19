# Polish program 1–10 — grill outcomes

Settled from the Matt polish workflow plan and prior Edge/debloat decisions (user approved workflow plan for execution). Not a product ADR — planning paper trail for `/to-spec` / `/to-tickets`.

## Constraints (non-negotiable)

- Edge stays installed; debloat-only; no uninstall automation or UI choice.
- Home-first; DMA restore-first; no maintenance payload; no Tier‑3 disables.
- No new product surface — deepen existing FirstLogon / debloat / authoring seams.

## Cut list

| Priority | Item | Track | Verdict |
|----------|------|-------|---------|
| Must (next smoke) | 1 Pins under lock | A | Ship |
| Must (next smoke) | 2 Winget catch-up honesty | A | Ship |
| Must (next smoke) | 4 DMA restore completeness | A | Ship |
| Next durability | 5 OOBE rehydration enumerate | B | Ship after A must |
| Next durability | 3 Live AppX cleanup / exempts | B | Ship after A must |
| Later | 6 Lock presenter acceptance signal | A | Later |
| Later | 9 WSL under-lock reboot/resume | A | Later (smoke stays mocked) |
| Later | 7 Home quiet-UX path collapse | B | Later |
| Later | 8 Edge ADMX refresh | B | Later (debloat keys only) |
| Later | 10 Wizard bridge JSON protocol | C | Later |

## Acceptance posture

- **Contract tests** required for every ticket.
- **VM smoke evidence** required for Track A must items (pins report, winget/runtime health signals where observable, DMA compliance including location when restore requests it).
- Pins remain **best-effort skip with report** for missing shortcuts unless apply-after-lock still fails with shortcuts present — then fail the pin step (not the whole FirstLogon) and surface in acceptance plumbing.

## Domain notes

No new glossary terms. Existing vocabulary: FirstLogon, DMA interop, provisioning lock, Profile, Payload, Smoke.

## Explicit non-goals

- Edge offline/online uninstall; DISM `/Remove-EdgeBrowser`; Tiny11-style folder scrub.
- Dev Drive default; AggressiveExperimental AI; CI VM acceptance (still deferred per ADR-009).
