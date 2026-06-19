# WinMint Roadmap

## Purpose

This roadmap is a living project document.

It has two jobs:

1. clearly state the **next development priorities**
2. keep the **broader strategic backlog** visible so WinMint does not optimize one area while neglecting the rest of the product

It is intentionally broader than a short-term sprint plan. It should still be readable as an execution document: the highest-priority tracks come first, each track is phased, and lower-priority tracks remain visible without pretending they are next.

## Current State

WinMint is no longer primarily blocked on backend architecture.

The project now has:

- a PowerShell module-first backend runtime under `src/runtime/modules/`
- explicit build contracts: `BuildProfile.json`, `BuildManifest.json`, `BuildDelta.json`, and `state.json`
- a headless engine that owns profile normalization, install-plan derivation, ISO/WIM servicing, setup payload staging, FirstLogon orchestration, reporting, and audit generation
- a GPUI frontend that can create intent, generate profiles, invoke builds, and render backend-generated review data
- a stronger contract and validation spine around setup payloads, FirstLogon, profile invariants, bootstrap behavior, and release boundaries
- an ephemeral default bootstrap path: `irm | iex` downloads and verifies a release in a unique temp session, launches from that session, and removes it afterward instead of installing into `%LOCALAPPDATA%\WinMint\versions`
- bootstrap failure handling that reports the active operation, failure category, reason, recovery guidance, and retry safety instead of surfacing only raw PowerShell errors
- a release readiness contract in `config/release-readiness.json`, with `docs/Release-Readiness.md` and validation checks keeping the public launch path, host requirements, and release gates aligned
- a hardware acceptance inventory in `config/hardware-acceptance.json`, with Surface Laptop 7 ARM64 first, tracked amd64 follow-up targets, profile links, driver requirements, destructive-install flags, and required evidence

The main project risk has shifted.

The hard problem is less "can the backend do the work?" and more:

- can acceptance be proven systematically
- can the GUI become the normal product surface
- can the live desktop result be made deliberate and polished

## Next Priorities

These are the current top priorities for continued development.

1. **FirstLogon and desktop experience maturity**
   Shell layers, launcher behavior, package installs, and live-user setup need stronger end-state validation and refinement. VM acceptance should prove the common live-user path before hardware installs begin.

2. **Live hardware acceptance**
   VM testing is necessary but not sufficient, but it is the current safety gate. The hardware inventory exists and the evidence loop is intentionally lightweight; real Surface Laptop 7 and x64 installs should wait until VM acceptance is green.

3. **GPUI completion**
   The GUI is real, but it is not yet the fully finished primary surface for users.

4. **Release and bootstrap regression discipline**
   The core public launch path is now defined and guarded. Keep it green through release readiness validation, clean-host smoke, and docs consistency as other product areas change.

5. **Hyper-V VM test architecture**
   Hyper-V is the acceptance gate before physical installs, not the highest product priority. The VM work should stay focused: prove unattended install, FirstLogon completion, evidence capture, and result evaluation well enough to safely move into real hardware acceptance.

The order above is deliberate:

- **FirstLogon and desktop maturity is first** because the installed system is the product outcome; if this is unreliable or visually unfinished, the ISO builder has not succeeded
- **live hardware acceptance is second** because WinMint must ultimately prove itself on real Surface and x64 machines, even though physical installs remain blocked until the VM gate is credible
- **GPUI completion follows the product proof tracks** because a polished frontend is valuable, but it should not outrun install confidence or live-user experience quality
- **release/bootstrap remains visible** because regressions in the public launch path can still block adoption even though A1-A3 are complete
- **Hyper-V architecture is fifth in product priority but still gates physical installs** because it is a safety mechanism and regression loop, not the product outcome itself

The order is still not rigid. If VM acceptance or release testing shows a higher-severity failure, that track should jump ahead.

## Track A — Release and Bootstrap Hardening

Phase A1, **Ephemeral Bootstrap and Clean Host Footprint**, is complete and no longer active roadmap work. The active code path is `winmint.ps1`; the regression guard is `tools/release/Test-WinMintReleaseLaunch.ps1`, which verifies SHA256 enforcement, packaged runtime shape, temp-session execution, cleanup, and the absence of a default `%LOCALAPPDATA%\WinMint\versions` release cache. Durable release caching remains an explicit opt-in through `-InstallRoot` or `-CacheRelease`.

Phase A2, **Failure and Recovery UX**, is complete and no longer active roadmap work. The bootstrapper now wraps failures with operation, failure kind, reason, recovery guidance, and retry safety. Release smoke covers the bad-checksum integrity path and verifies cleanup still happens after failure.

Phase A3, **Public Usage Readiness**, is complete and no longer active roadmap work. The release readiness bar is documented in `docs/Release-Readiness.md`, backed by `config/release-readiness.json`, checked by repository validation, and exercised by release smoke. Future release work is regression discipline unless a concrete launch failure reopens Track A.

## Track B — Live Hardware Acceptance

### Phase B1 — Acceptance Inventory

Phase B1, **Acceptance Inventory**, is complete and no longer active roadmap work. The inventory is `config/hardware-acceptance.json`; the runbook is `docs/Hardware-Acceptance.md`; repository validation enforces profile existence, architecture matching, SurfaceCatalog use for Surface Laptop 7, and required evidence/check coverage.

### Phase B2 — Evidence Loop

Goal: make live installs produce reusable evidence.

Status: deferred behind Track D. The runbook now defines a manual evidence folder, required copied artifacts, and `notes.md` contents, but physical installs should not begin until VM acceptance is credible. Do not add a collector or evidence-package schema until real Surface and x64 runs show repeated manual collection pain.

Work:

- complete the VM acceptance path in Track D before the first real-machine install
- collect the first Surface Laptop 7 evidence folder after a real install
- collect at least one x64 evidence folder after a real install
- use live install audit output as structured feedback rather than incidental diagnostics
- convert repeated findings into focused contract tests or product fixes

Exit criteria:

- VM acceptance has passed enough to make physical installs a hardware-specific validation step, not the first end-to-end test
- hardware acceptance produces comparable evidence instead of one-off observations

### Phase B3 — Ongoing Regression Coverage

Goal: make hardware acceptance sustainable over time.

Work:

- decide which profiles are recurring regression profiles
- decide which checks are release-gating versus occasional deep validation
- keep the matrix realistic for available hardware

Exit criteria:

- hardware validation remains practical and deliberate

## Track C — FirstLogon and Desktop Experience Maturity

### Phase C1 — FirstLogon Reliability

Goal: strengthen live-user setup as a product surface rather than a best-effort script chain.

Work:

- continue hardening resumability and idempotency
- improve optional-module isolation and diagnostics
- refine retryable and reboot-requiring flows
- ensure module success means real end-state success, not only command completion

Exit criteria:

- FirstLogon failures are narrower, clearer, and easier to recover from

### Phase C2 — Shell-Layer Maturity

Goal: make shell selections produce a polished desktop, not just installed packages.

Work:

- improve `windhawk` preset confidence and lifecycle handling
- improve `yasb` + `thide` combined behavior and end-state ergonomics
- improve `komorebi` + `whkd` defaults and workspace behavior
- refine `nilesoft` integration
- align the actual installed desktop with UI preview intent

Exit criteria:

- selected desktop layers result in a desktop that feels deliberate and finished

### Phase C3 — Launcher and Desktop Integration

Goal: finish the user-facing experience around Raycast, Search fallback, tray behavior, and shell coexistence.

Work:

- verify launcher key behavior across launcher/no-launcher paths
- confirm Raycast extension curation remains intentional
- refine status icons and startup behavior
- ensure desktop layers and launcher behavior coexist predictably

Exit criteria:

- launcher and shell behavior feels like one product, not separate features stitched together

## Track D — Hyper-V VM Test Architecture

Track D is the current acceptance gate before Track B physical installs. It is
not the highest product priority, but it must be credible before real machines
are used for destructive ISO testing.

### Phase D1 — VM Testing Model

Goal: turn the current collection of scripts into an explicit test system.

Status: the explicit model now exists. `tools/vm/Invoke-WinMintVmAcceptance.ps1`
is a single orchestrator (build + boot → wait for FirstLogon → inspect → evidence)
delegating to the existing single-purpose scripts, and `docs/VM-Acceptance.md`
documents what each script owns and the Pro/unattended invariant. Remaining D1
work is mostly proving the model by running a real green pass and folding the Edge
experiment / future test classes into it deliberately.

Work:

- define VM test classes: install smoke, unattended install, first-logon completion, shell/app acceptance, audit runs, diagnostics
- define the boundaries between profile fixture, ISO build, VM provisioning, guest execution, evidence collection, and result evaluation
- make the Pro-for-Hyper-V invariant a first-class design rule

Exit criteria:

- VM testing has named layers and responsibilities — **met** (`docs/VM-Acceptance.md`)
- maintainers can explain what each script owns — **met** (phase/ownership table)

### Phase D2 — Harness Restructure

Goal: make VM testing composable and repeatable.

Status: partially met. The orchestrator supports attaching to a running VM
(`-SkipBuild`) and writes a standardized evidence directory
(`output/vm-acceptance/<vm>-<stamp>/` with `acceptance-result.json`). Remaining
work is reducing ad hoc coupling between the underlying build/VM/guest/rerun/log
helpers rather than adding more orchestration surface.

Work:

- restructure the harness into explicit phases
- reduce ad hoc coupling between build, VM creation, guest mutation, rerun, and log collection helpers
- standardize output layout and evidence directories
- support partial reruns at deliberate boundaries

Exit criteria:

- VM runs can be resumed and inspected by phase
- the harness no longer feels like a loose collection of convenience scripts

### Phase D3 — Scenario Matrix

Goal: stop overloading one VM profile with too many product concerns.

Work:

- define a small matrix of VM acceptance profiles by purpose
- split browser/editor/WSL checks from shell-layer checks where useful
- decide which desktop-layer and launcher scenarios belong in VM acceptance versus live hardware
- keep scenarios narrow enough that failures are attributable

Exit criteria:

- VM scenarios are intentional and diagnosable

### Phase D4 — Evidence and Evaluation

Goal: make VM outcomes machine-readable and comparable across runs.

Work:

- define required evidence artifacts
- evaluate success/failure from `BuildManifest`, `BuildDelta`, setup logs, and `state.json`
- standardize result summaries
- prepare the harness for future gated automation, even if full VM runs stay local for now

Exit criteria:

- VM acceptance outcomes are systematic, not mostly manual interpretation

## Track E — GPUI Completion

### Phase E1 — Wizard Completion

Goal: complete the main GUI flow as a full profile-authoring surface.

Work:

- finish the Configure, Build, and Review flows
- ensure all important profile dimensions are visible and understandable
- keep the frontend strictly contract-driven

Exit criteria:

- a realistic WinMint build can be authored end-to-end through GPUI

### Phase E2 — Review and Reporting UX

Goal: make the review experience genuinely useful before a build.

Work:

- deepen `BuildDelta` rendering
- group change summaries by phase and subsystem
- explain keep/suppress behavior clearly
- keep artifact paths secondary to the actual planned-change story

Exit criteria:

- the review page answers "what will change?" without raw JSON inspection

### Phase E3 — Build Execution UX

Goal: make the GUI comfortable during long-running real usage.

Work:

- improve progress presentation
- improve failure-state clarity
- improve artifact discovery after builds
- keep elevation and relaunch flows understandable

Exit criteria:

- GUI builds are understandable during execution and after failure

### Phase E4 — Product Polish

Goal: make GPUI feel like the primary user-facing product.

Work:

- refine navigation, layout, component consistency, and state handling
- tighten packaged GUI assumptions
- keep Rust logic frontend-only while still making the app feel complete

Exit criteria:

- the packaged GUI feels like the normal WinMint experience

## Track F — Reporting and Audit Polish

### Phase F1 — Human-Facing Summaries

Goal: make backend-generated outputs more useful to humans.

Work:

- improve manifest and delta summaries
- ensure CLI and GUI review surfaces align
- make reports more useful after real builds and installs

Exit criteria:

- reports are useful as evidence, not only as raw artifacts

### Phase F2 — Audit Usefulness After Install

Goal: make audit output a real feedback mechanism for product refinement.

Work:

- refine live-install audit output
- better connect audit findings to profile/setup/first-logon behavior
- define which warnings matter most for release readiness

Exit criteria:

- audit results feed roadmap prioritization directly

## Track G — CLI and Product Surface Polish

### Phase G1 — CLI Ergonomics

Goal: keep the CLI coherent even if GPUI becomes the default path.

Work:

- improve help text and failure messages
- ensure `new`, `build`, `validate`, `list`, and `clean` remain coherent
- keep JSON and human output predictable

Exit criteria:

- CLI remains a strong headless interface, not a neglected fallback

### Phase G2 — Cross-Surface Consistency

Goal: ensure CLI, GUI, reports, and docs all describe the same product.

Work:

- align wording and behavior across surfaces
- keep contract-driven behavior authoritative
- prevent UI/CLI drift on defaults and option meanings

Exit criteria:

- the product reads as one system, not multiple competing surfaces

## Track H — Documentation and README Maturity

### Phase H1 — Documentation Boundaries

Goal: reduce both under-documentation and over-documentation.

Work:

- tighten what belongs in `README.md`, `AGENTS.md`, and `docs/`
- remove stale or duplicative detail
- keep executable truth in contracts and tests, not documentation drift

Exit criteria:

- docs are clearer, smaller where possible, and more trustworthy

### Phase H2 — Root README Maturity

Goal: make the repo front page feel like a mature GitHub-facing project.

Work:

- improve the product pitch and current-status framing
- explain what WinMint is, who it is for, and what its safety/product stance is
- present realistic setup and usage paths
- improve architecture and roadmap summaries for readers

Exit criteria:

- the root README looks intentional, credible, and current

## Lower-Priority / Future Tracks

These are not unimportant. They are simply not the most urgent right now.

### Distribution Variants

- future installer choices beyond the current bootstrap and zip path
- possible packaging refinements for different user audiences

### Broader Automation

- more CI-friendly validation where Windows host restrictions permit it
- stronger automated release verification

### Additional UX Surfaces

- first-logon status/demo UI maturation
- future visual/reporting helpers if they stay aligned with the headless backend

## Roadmap Maintenance Rules

When this roadmap changes:

- keep **Next Priorities** short and explicit
- keep each major track phased
- do not pretend lower-priority tracks are unimportant; keep them visible
- promote a lower-priority track when evidence says it is blocking adoption, correctness, or user trust
- remove completed phases instead of letting the roadmap become a graveyard

## Definition of Wider Readiness

WinMint is not ready for broader real-user usage merely because one area looks polished.

Wider readiness requires credible progress across:

- release and bootstrap trust
- VM acceptance structure
- live hardware evidence
- FirstLogon and desktop-layer maturity
- a product-quality GUI or clearly acceptable CLI/bootstrap fallback
- trustworthy docs and project presentation

That is why this roadmap is broader than only GPUI and VM testing, even though those remain important tracks.
