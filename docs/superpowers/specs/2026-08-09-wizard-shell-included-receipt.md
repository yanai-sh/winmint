# Wizard shell: Media → You → Taste → Included

**Date:** 2026-08-09  
**Status:** Spec (grill confirmed) · issue to follow  
**Glossary:** [CONTEXT](../../../CONTEXT.md) (Wizard, Included, Taste, Keep-flag, Profile)  
**Prior:** [Wizard UX Phase A](2026-08-05-wizard-ux-phase-a-design.md) · Prototype: `prototypes/wizard-oobe-moodboard/`  
**Research:** [ReviOS ISO](../../research/2026-08-09-revios-iso-vs-winmint.md) · [Rectify11/Revi host UX](../../research/2026-08-09-rectify11-revios-host-ux.md)

## Problem Statement

The Avalonia Wizard still uses a Phase A shell (Source → Configure → Preview → Review) that buries identity, flattens taste into one Configure pile, and treats Preview/Review as plan dump + save rather than a compose **receipt**. Users cannot see—at a glance—what this build will strip, install, and stamp quietly (ADR-009 product constants) before they Build. The moodboard prototype and 2026-08-09 grill locked a clearer OOBE-like shell; product code has not caught up.

## Solution

Rebuild the Wizard shell to **Media → You → Taste → Included** (stage morph/scrub). Taste is skippable (“Use defaults” → host `recommended`). Included is the compose **receipt**: pick strip, ADR-009 quiet block, collapsed What’s included (friendly names), short Plan meta. Build stays on the status bar; gates are Source ISO + password. Compose continues through Avalonia-free `WizardSession` / `KeepFlagPresets` — no second planner, no BuildPlan/schema change for this UX regroup.

## User Stories

1. As a maintainer, I want Wizard stages named Media → You → Taste → Included, so that the host flow matches the grilled product language.
2. As a maintainer, I want Media to collect Source ISO path and image-quality lane (and optional WIM index if already present), so that I start from media before identity.
3. As a maintainer, I want You to require local account username + password (autologon), so that Plan never accepts a blank password.
4. As a maintainer, I want Taste to hold package chips, keep chips (Gaming, Copilot), and recommended debloat posture in one dense stage, so that I am not marched through thin Apps/Desktop/Linux panes.
5. As a maintainer, I want to skip Taste with “Use defaults,” so that zero-config uses host `recommended` + product defaults without editing chips.
6. As a maintainer, I want Included to show a quiet summary of this compose, so that I know what I’m about to build before Save/Build.
7. As a maintainer, I want a pick strip on Included for my Taste choices and packages (and `recommended` removals as friendly names), so that user intent is visible without raw catalog ids.
8. As a maintainer, I want “also applied quietly…” to list only ADR-009 product constants, so that silent policies are disclosed without double-listing remove-list items.
9. As a maintainer, I want a collapsed “What’s included” section with friendly names, so that I can deepen without a package-id wall.
10. As a maintainer, I want short Plan meta on Included (network / DMA / lane), so that Plan-derived facts appear without a dashboard.
11. As a maintainer, I want Build on the status bar gated on Source ISO + password (and existing Save→Apply rules), so that I cannot build from an incomplete identity or missing media.
12. As a maintainer, I want stage morph/scrub navigation between the four stages, so that the shell feels like one composition, not a wizard parade of peer tabs.
13. As a maintainer, I want Keep Gaming and Keep Copilot as the only keep chips in alpha, so that preset math stays small.
14. As a maintainer, I want preset names never written into Profile JSON, so that ADR-005 keep-flag polarity holds.
15. As a maintainer, I want packages to appear on the same pick strip as Taste choices, so that Included does not invent a second packages UI.
16. As a maintainer, I want DMA and other silent host defaults to remain host-filled unless already exposed, so that Configure soup does not return on You/Taste.
17. As a maintainer, I want Save Profile then elevated Build (Phase B path) to keep working after the shell rename, so that ImageServicing.Apply is unchanged.
18. As an agent implementing this, I want S1b tests to keep proving preset/overlays/packages → Profile → Plan, so that UX regroup cannot break compose.
19. As an agent, I want any new stage/gate rules (skip Taste, password before Included/Build) proven at a pure model seam if automated, so that Avalonia UI automation is not required.
20. As a maintainer, I want friendly names in the receipt and catalog ids only in digests/logs, so that humans and agents each get the right fidelity.
21. As a maintainer, I want `recommended` AppX/caps growth only when I hit a real need later—not in this ticket—so that this work does not expand KeepFlagPresets lists.
22. As a maintainer, I want no Untouched/Broken marketing catalogs in alpha, so that honesty stays Design §1 depth until evidence exists.
23. As a maintainer, I want no in-product Windows ISO download, so that ADR-001 Source ISO contract holds.
24. As a maintainer, I want no empty-CAB / WinSxS “newer component” supersede as product debloat, so that remove-list + ADR-009 remain the mutation model.
25. As a maintainer, I want residual erase posture unchanged (no durable Revision Tool–like surface), so that ADR-008 holds.
26. As a maintainer, I want the moodboard prototype treated as a visual/IA reference only, so that Avalonia owns the shipping shell.
27. As a maintainer, I want Preview’s plan-dump role folded into Included’s receipt (not a fifth stage), so that stage count stays four.
28. As a maintainer, I want Review’s Save/Build affordances available from Included + status bar, so that Save→Build is not lost.
29. As a maintainer, I want Cli `build` recipe / handoff text still available where Phase A showed it, so that headless rebuild remains copy-pasteable.
30. As a maintainer, I want `just check` green after the shell rebuild, so that Smoke/S1b contracts stay intact.

## Implementation Decisions

- **Scope:** Wizard shell + Included receipt UX only. No Profile schema bump; no BuildPlan opcode changes; no KeepFlagPresets list expansion.
- **Compose seam (required):** Keep `WizardSession.ComposeAndPlan` / `WizardSessionInput` as the Avalonia-free path. ViewModels bind stages → same input → Profile + Plan.
- **Stage model:** Four stages — Media, You, Taste, Included. Map today’s Source→Media; identity fields→You; Configure chips/preset/keeps→Taste; Preview+Review→Included (+ status-bar Build).
- **Taste skip:** “Use defaults” / scrub past Taste leaves host preset `recommended` with KeepGaming/KeepCopilot false unless user set them; packages empty unless previously chosen.
- **Included receipt layers:** (1) quiet summary, (2) pick strip, (3) ADR-009 quiet block only, (4) collapsed What’s included (friendly names), (5) short Plan meta (requiresNetwork / DMA on / lane).
- **Quiet vs picks:** Product constants (EdgeDebloat, OneDrive, device metadata, WPBT, Reserved Storage; Copilot kill unless kept; BraveDebloat iff Brave) → quiet block. `recommended` removals → strip / collapse, not quiet.
- **Keep chips (alpha):** Gaming + Copilot only.
- **Friendly names:** Receipt UI uses human labels; Profile/Plan/digests keep catalog ids.
- **Gates:** Cannot advance from Media without existing Source ISO; cannot reach Build without password (and existing Save-before-Build rule unless explicitly relaxed in implement — default: keep Save→Build).
- **Optional pure seam:** Extract stage index + CanAdvance/CanBuild rules from the ViewModel into a small Avalonia-free helper only if tests need it; do not add UI automation.
- **Stack:** Existing Avalonia + CommunityToolkit.Mvvm; no WebView2; no custom third-party OOBE in guest.
- **Docs:** CONTEXT Already defines Included/Taste/Wizard target shell; update DESIGN shipped/unlocked notes when implemented; prototype remains under `prototypes/`.
- **Prototype note:** Moodboard `STAGES` (media · you · taste · included), Taste skippable, password before Included/Build encodes the stage machine — implement in Avalonia, do not ship HTML.

## Testing Decisions

- Good tests assert **external compose behavior**: given session input (preset, keeps, chips, account), Profile JSON and Plan artifacts match — not Avalonia control trees.
- **Primary seam:** S1b — `WizardSessionTests`, `KeepFlagPresetTests`, `WizardPackagesTests` (and catalog tests as needed). Extend only if receipt **formatters** are pure functions beside session (friendly-name lists from remove-lists / ADR-009 set).
- **Optional seam:** Pure stage/gate model tests for skip Taste + password/ISO gates — only if that helper is introduced.
- **Out of automated scope:** Pixel morph/scrub, Fluent chrome, screenshot diffs.
- **Regression:** `WizardBuildTests` still prove Save path → Apply glue with fake runner; `just check` green.
- Prior art: `docs/TDD.md` S1b; existing Wizard session tests.

## Out of Scope

- Expanding `recommended` AppX/capability/feature lists
- Empty-CAB / WinSxS supersede debloat
- In-product ISO download; hardware bypass marketing; Defender-disable gates
- Untouched/Broken honesty catalogs; durable post-install branded tweak app
- Wizard edition probe / rich per-stage DISM progress (still policy-out unless separate issue)
- Guest Splash / ProvisioningSession changes
- Schema `v2`; Profile presets-in-JSON
- Replacing BuildPlan or ImageServicing
- Shipping the HTML moodboard as product UI

## Further Notes

- Grill locks 2026-08-09: Included = compose receipt; honesty depth = Design §1; quiet = ADR-009 only; keep chips = Gaming + Copilot; collapse = friendly names; packages on pick strip; shell accepted.
- Do not apply `ready-for-agent` until an implement session starts ([issue-tracker](../../agents/issue-tracker.md)).
- Follow-on: `/to-tickets` if the implementer wants tracer splits (shell nav vs receipt formatters vs AXAML polish).
