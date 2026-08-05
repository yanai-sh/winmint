# Wizard UX Phase A — design lock

**Date:** 2026-08-05  
**Status:** Locked (grill) · implement in-repo

## Locks

| Topic | Decision |
|-------|----------|
| Role | Wizard = shell for Profile + RunOptions; shared plan/build path later — not a second planner, no in-process DISM |
| Vertical | Phase A only — shell + authoring/plan/save |
| Build control | Disabled / “Phase B”; after Save show Cli `build` recipe |
| Source | Existing ISO path + Test\|Release lane + optional WIM index; no edition probe |
| Configure | Hybrid chips + advanced multiline; v2 remove-list / package-id polarity |
| Stack | XAML + CommunityToolkit.Mvvm + compiled bindings; `WizardSession` Avalonia-free |
| Docs | CONTEXT + DESIGN unlock; ADR-004 footnote for CommunityToolkit.Mvvm (no ADR-008) |
| Chrome | Custom Avalonia titlebar + dark Fluent palette + v1 brand hero assets |

## Out (Phase B / later)

Elevated build invoke, progress UI, edition probe, WebView2, live winget search.

## UX follow-up (2026-08-05)

Configure copied from v1: curated Posture / Keep / Browsers / Editors / Shell / WSL chip panels only — no catalog dump or account/DMA form soup (silent defaults). Chrome: stock Fluent + Mica, OS light/dark.
