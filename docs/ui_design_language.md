# WinMint UI Design Language

Last reviewed: 2026-05-17

This is the design foundation for the primary GPUI shell. It is not a
replacement for the headless builder. It is a reusable language for making the
GUI feel intentional while keeping the app simple enough to remain fun.

## Philosophy

WinMint is a cinematic ISO builder, not a dashboard. The UI should feel like a
sparse, staged flow for creating intent, checking readiness, launching work, and
reading the result.

The interface should prefer:

- Intent over options.
- Status over decoration.
- Preview over explanation.
- Coarse profile groups over granular toggles.
- Reusable modules over one-off screens.
- Native platform behavior where GPUI exposes it cleanly.
- Staged focus over dense dashboards.

The GUI exists to make the build feel pleasant and inspectable. The CLI remains
the source of truth for serious use.

## Brand Use

Use the checked-in brand assets with one source of truth:

- `assets/brand/WinMint.svg` is the canonical mark master for authoring.
  Original leaf arrives as embedded PNG inside `<image data:…>` alongside
  named vector pane paths (regenerated via `Export-WinMintBrandVariants.ps1`).
- `assets/brand/winmint-mark-v2.svg` is the **vector-traced** mark authoring file
  (VTracer); keep edits here when tuning pane/leaf fidelity.
- `assets/brand/WinMint.vector.svg` is the **GPUI runtime** sibling: published from
  v2 via `tools/brand/Build-WinMintVectorMark.ps1` → `publish_vector_mark_from_v2.py`
  (drops degenerate `<path d="">`). Embedded raster subtree nodes disappear under
  resvg without `raster-images`; never load `WinMint.svg` directly in GPUI for the mark.
- `tools/brand/build_vector_winmint_mark.py` remains a **fallback** that approximates the
  leaf outline from raster-in-WinMint.svg when v2 hasn’t been updated yet (`Build-WinMintVectorMark.ps1 -RasterTrace`).
- `assets/brand/winmint-brand-final.svg` is the full lockup source for the
  splash page when the app wants the complete brand presentation.
- `assets/brand/winmint-brand-final.png` is the rendered splash runtime asset.
  Regenerate it from the SVG; do not hand-edit it.
- Generated flat, dark, plain, or optimized variants are optional build
  artifacts only. Do not treat them as separate brand sources or runtime
  defaults.

The UI should compose the lockup from the master mark plus live text. The mark
carries the mint leaf; the whole app must not become a mint-themed interface.
Do not inline generated SVG contents into Rust.

For runtime theming, use the canonical self-contained mark first. If a derived
asset is needed for diagnostics, generate it from the master with
`tools/brand/Export-WinMintBrandVariants.ps1 -Variants`. Theme the Windows
panes and live wordmark; do not redraw, recolor, or replace the leaf artwork.
Do not maintain separate hand-edited dark, flat, or mono SVGs.

## Visual Tone

The tone is native, sparse, and touch-friendly:

- GPUI's default neutral palette first.
- Windows/system blue for selected and primary actions.
- The mint leaf stays inside the brand mark.
- Warm amber only for attention and source-prep warnings later.
- Red only for destructive or failed states.

Avoid decorative gradients, dashboard grids, KPI surfaces, and dense inspector
layouts. The app may open on a brand-led splash, but the first real interaction
should be a focused source/action stage.

## Layout Model

The GPUI shell should use a staged layout:

- Splash: brand mark, live wordmark, one primary action.
- Source: one large source target with verification/status below it.
- Profile: coarse group choices, architecture, and only visible follow-up
  options when needed.
- Review: compact intent summary and explicit write action.

Status belongs near the active stage, not in a persistent dashboard chrome. It
should always be obvious whether the app is waiting on source input, shaping
intent, or ready to write the bridge artifact.

## Component Vocabulary

Start with a small reusable set:

| Component | Purpose |
|-----------|---------|
| App frame | Owns the canvas, titlebar slot, and bottom status strip. |
| Brand lockup | Uses the master mark plus live wordmark text. |
| Surface | Reusable bordered panel for grouped controls. |
| Section label | Compact title and supporting line for any panel. |
| Selectable card | Profile groups, architecture choices, shell layers. |
| Pill | Tiny state marker such as `Ready`, `Passwordless`, `Dry run`. |
| Field shell | Wireframe placeholder for future native input controls. |
| Timeline step | Build stages without implying work has happened yet. |
| Command card | Shows the PowerShell bridge, output path, and debug action. |
| Status bar | One-line status plus primary action. |

Keep components boring first. If a component needs custom drawing, prove that it
cannot be expressed with `div`, `img`, text, and GPUI interactions.

## Interaction Rules

- Every click target should correspond to a clear intent mutation or command.
- Keyboard actions should be added through GPUI `actions!` and key contexts.
- Source selection should support native path picker first, then drag/drop.
- Output and manifests should have reveal/copy actions.
- Destructive or network/conversion work must use explicit prompts.
- Custom titlebar visuals must use GPUI `WindowControlArea` hit regions.

## Boundary Rules

- UI components may display derived state, but they do not own engine policy.
- Rust may hold a UI-side intent model, but PowerShell remains the profile
  resolver.
- Do not duplicate AppX policy, package source policy, UUP conversion policy,
  or FirstLogon derivation in GPUI.
- The UI scaffold may stay wireframe-level until it can create and validate a
  real `BuildProfile.json`.

## Current Implementation

The GPUI app now has:

- `theme.rs` for colors, asset paths, and shared sizing constants.
- `components.rs` for brand primitives, Fluent icon blocks, scrub strip, dashed
  ISO landing well (with OS drop affordance), posture tiles, segmented arch,
  and chip toggles.
- `intent.rs` for deterministic `intent.json` (including `ISOPath`, toolkit and
  desktop-layer fields consumed by `New-UiBuildProfile.ps1`).
- `main.rs` composing **cinematic beats**: Landing → Stance → optional Toolkit /
  DesktopShell → Finish, with staged navigation rather than inspector rails.

Next steps: tighten entity-backed intent state (instead of growing the view),
source probe/readiness (Phase 2), manifest/log surfaces, keyboard `actions!` for
write intent / navigation, clipboard path paste where it fits platform input.
