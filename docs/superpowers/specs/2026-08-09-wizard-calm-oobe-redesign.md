# Wizard shell redesign — calm OOBE + vanilla diff

**Date:** 2026-08-09  
**Status:** Design (approved in grill)  
**Related:** BuildPlan host · [ADR-009](../../decisions/ADR-009-product-constant-policies.md) · product-constant MinGit/Nilesoft · Primary gate parked deepening note: this is maintainer-requested Wizard UX, not architecture T2–T4

## Problem

The Media → You → Taste → Included shell uses cute stage names, dense chip carnival energy, and weak disclosure of what WinMint actually changes versus a stock Microsoft ISO. Users need a calm OOBE-like path and an optional full view of every modification.

## Solution

Rebuild the Avalonia Wizard as a **4-step calm install guide** with plain names, WinMint branding + modern Windows (Fluent) chrome, locked Copilot/gaming posture, desktop-shell stubs, and a Review **Show full plan** that is a **vanilla → WinMint diff** driven by the real Plan.

## Steps

| # | Name | Job |
|---|------|-----|
| 1 | **Source** | Microsoft ISO path, WIM index/edition, Test \| Release |
| 2 | **Account** | Local username + password, Wi‑Fi during setup, DMA settle region |
| 3 | **Software** | Browsers, editors, desktop shell, WSL, cleanup preset (recommended). Advanced multiline collapsed |
| 4 | **Review** | Short receipt + **Show full plan** (vanilla diff) + Save / Build |

Nav: plain `1 Source · 2 Account · 3 Software · 4 Review` (or thin progress). Drop MEDIA/YOU/TASTE/INCLUDED scrub labels.

**Skip:** Software “Use defaults” → recommended cleanup, no optional packages → Review. Product constants still always install.

**Gates (unchanged):** Source ISO before leaving Source; password before Build; Save-before-Build unless already saved.

## Software step

- **Browsers / Editors / WSL** — curated chips (Edge = keep, not a remove chip).
- **Desktop shell (stubs):** Windhawk, YASB, Komorebi, FancyWM — **default none selected**. Windhawk/YASB/Komorebi catalog-backed; FancyWM catalog stub until package id verified.
- **Cleanup:** host preset **recommended** only (no Acceptance/Empty carnival required in primary UI; advanced may keep escape hatch if needed).
- **Removed from UI:** Keep gaming, Keep Copilot toggles.
- **Not chips:** MinGit, Nilesoft Shell (product constants — quiet + full plan only).

## Copilot / gaming product lock

- **Always remove** gaming AppX families (recommended gaming set).
- **Always remove** Copilot **app** (`Microsoft.Copilot`).
- **Keep Copilot in Edge** — do **not** stamp Edge/Windows Copilot-kill policies (`HubsSidebarEnabled=0`, `TurnOffWindowsCopilot=1`).
- Split today’s single `keepCopilot` behaviour: AppX strip stays; Edge Copilot policies stay off the kill list. Wizard does not expose toggles. Plan/ADR-009 docs updated in implement.

## Review — short receipt

Calm summary: account, region, selected apps/shell/WSL, “quiet defaults on,” lane, network needed. Primary **Build**.

## Review — Show full plan (vanilla diff)

**Question answered:** How does this ISO + FirstLogon differ from an untouched Microsoft ISO with this Profile?

Two sections (Plan-sourced, not hand-waved):

1. **During image build (offline)** — WIM/ISO mutations: removes (when offline AppX venue), caps/features, Surface drivers, offline policy stamps (Edge debloat, OneDrive disable, WPBT, …), Shell stamp, payload/jobs staging, export lane.
2. **After first sign-in (live)** — DMA settle, online AppX safety-net, product-constant jobs (OneDrive uninstall, Reserved Storage, MinGit, Nilesoft), user packages/WSL, DoH if set, unlock.

Each row: concrete modification + **always** vs **you chose**. Plain label; technical id secondary. No inventing tweaks WinMint does not perform.

## Visual — WinMint + modern Windows

- **Brand:** existing WinMint mark + wordmark (titlebar / hero as appropriate). Wordmark language stays **Win blue → mint** (`#003984` / `#1170f2` / `#4cd08c` family from `assets/brand`) — use sparingly (logo, quiet accents), not a full custom theme takeover.
- **Chrome:** FluentTheme, follow **OS light/dark**, **OS accent** for primary Continue/Build. Mica/transparent titlebar OK when it reads as modern Windows, not decoration for its own sake.
- **Layout:** calm OOBE density — airy step title + one supporting sentence; sober chips; wide content.
- **Type:** Segoe UI Variable / Fluent defaults.
- **Motion:** light step crossfade; respect reduced motion.
- **Avoid:** cute stage theater, dark terminal cosplay, purple/glow AI defaults, inventing a second brand.

## Implementation notes (for plan)

- Rename stages in `WizardStageGates` + views (`Source` / `Account` / `Software` / `Review`); remap ViewModels/commands/tests.
- `IncludedReceipt` → Review receipt + new **PlanDiff** (or similar) builder from `BuildArtifacts` stages/jobs/policySpecs.
- ProductConstantPackages + Copilot policy split in Orchestrator; Wizard strip toggles; FancyWM catalog stub.
- Keep `WizardSession` Avalonia-free compose seam; extend tests for stage names, locked gaming/Copilot, plan diff rows, shell stubs.

## Out of scope

- Architecture deepening T2–T4  
- Changing Smoke Hyper-V harness UX  
- Shipping FancyWM install before catalog verification  
- BitLocker / Microsoft account modes  
- Replacing BuildPlan with a second planner  

## Success

A maintainer can build an SL7 wipe Profile without reading “Taste,” see optional apps clearly, cannot flip gaming/Copilot app/Edge-Copilot kill, and can open **Show full plan** to audit every vanilla delta before Build.
