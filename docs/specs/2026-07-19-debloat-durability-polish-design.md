# Spec: Debloat durability polish (Track B)

**Date:** 2026-07-19  
**Status:** Ready for tickets  
**Parent grill:** [2026-07-19-polish-program-grill-outcomes.md](2026-07-19-polish-program-grill-outcomes.md)  
**Research:** [docs/research/2026-07-19-polish-primary-sources.md](../research/2026-07-19-polish-primary-sources.md)

## Problem Statement

WinMint removes consumer noise offline and at SetupComplete/FirstLogon, but apps and tips can return: OOBE Orchestrator/UScheduler jobs rehydrate inbox apps, live AppX cleanup drifts from the catalog on push-only ISOs, Home quiet-UX is split across Enterprise-skewed policies and live ContentDeliveryManager edits, and Edge gains new promo ADMX keys over time. Users see bloat come back after a “clean” install.

## Solution

Make debloat durable: enumerate and suppress known rehydration jobs (starting with documented Outlook controls), keep live AppX exempt lists restage-safe, collapse Home quiet-UX to one verified path, and periodically extend `edge-policy-minimal` with noise-only ADMX—never uninstall Edge or touch Copilot page-context/sidebar.

## User Stories

1. As an installer, I want new Outlook / Chat-class rehydration blocked when WinMint removed those surfaces, so that they do not return days later.
2. As an installer, I want live AppX cleanup to honor the same exempt prefixes as offline servicing, so that push-only ISOs do not strip Store/WebView2.
3. As an installer, I want leftover consumer AppX reported or retried when safe, so that OEM/inbox junk does not silently remain.
4. As a Home user, I want tips and suggested-apps noise quieted by a path that actually works on Home, so that CloudContent Enterprise policies are not my only hope.
5. As a user who keeps Edge, I want promotional/AI-adjacent Edge noise reduced as Microsoft adds policies, so that debloat stays current.
6. As a user who keeps Edge, I want Copilot page-context chat and the sidebar available, so that useful browser features survive debloat.
7. As a maintainer, I want contract tests locking OOBE suppress keys and Edge policy names, so that catalog drift fails CI.
8. As a smoker, I want guest removal-drift tools to remain the source of truth for AppX leftovers, so that acceptance can flag incomplete cleanup.

## Implementation Decisions

- OOBE: prefer Microsoft-documented Outlook UScheduler controls; extend enumeration carefully for other Orchestrator keys; do not blanket-delete unknown jobs.
- Live AppX: eliminate hardcoded exempt fallback drift by always staging exempt prefixes in setup profile; optional repair loop may use existing guest drift inventory—never remove Tier‑0 packages.
- Quiet UX: audit which CloudContent policies Home honors on 25H2; prefer the live ContentDeliveryManager/quiet path as the Home source of truth; drop redundant ineffective stamps.
- Edge ADMX: additive noise policies only from research list; forbid `HubsSidebarEnabled=0` and page-context Copilot killers; Edge remains installed (`keep.edge` const true).

## Testing Decisions

- Contract-test setup action / tweak catalogs for expected suppress keys and Edge policy names.
- Reuse ProfileInvariant StaticAssertions patterns for Edge forbidden policies.
- Guest removal-drift tools for AppX durability evidence where VM runs.

## Seams

1. SetupComplete OobeRehydration result artifact.
2. Setup profile `appxSystemExemptPrefixes` + FirstLogon/SetupComplete AppX cleanup.
3. `edge-policy-minimal` / tweaks.json parity contracts.
4. FirstLogon quiet UX / cloud-content policy selection.

## Out of Scope

- Edge uninstall (any path); IntegratedServicesRegionPolicySet patches; WebView2 removal; AggressiveExperimental AI; broad OEM AppX expansion without catalog proof.

## Further Notes

Must-after Track A: OOBE enumerate, then live AppX. Quiet UX and Edge ADMX are later capacity work.
