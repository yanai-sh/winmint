# Spec: Ship no-clone Quickstart (`winmint.yanai.sh`)

**Date:** 2026-08-10  
**Plan:** `.cursor/plans/no-clone_score_nine_90686cf0.plan.md` (implementation already on `dev`, uncommitted)  
**Tracker:** GitHub issue (this cutover)

## Problem Statement

WinMint’s README promises `irm https://winmint.yanai.sh | iex`, but live Quickstart fails until bootstrap lives on **main**, the Cloudflare Worker is redeployed, and a GitHub Release publishes the verified toolkit zip. Users must not need a git clone or source zip.

## Solution

Finish the ops cutover: land the no-clone work on **main**, deploy the Worker, publish a `v*` toolkit Release, and cold-verify `irm | iex` launches the Wizard without a checkout. Do not claim Primary / bare-metal wipe proven.

## Seam under test

One external seam: **`irm https://winmint.yanai.sh | iex`** → bootstrap text → GitHub Release zip + `.sha256` → temp toolkit → Wizard (default) or Cli (`/cli`).

No new product modules. Prefer existing pack script, `winmint.ps1`, and Worker under `cloudflare/winmint`.

## User Stories

1. As a WinMint user, I want `irm https://winmint.yanai.sh | iex` to start the Wizard, so that I never clone the repo or download a source zip.
2. As a WinMint user, I want the downloaded toolkit to be SHA-256 verified, so that I trust what I run.
3. As a WinMint user, I want `/cli` to launch headless Cli, so that scripted plan/build works without the GUI.
4. As a WinMint user, I want README Quickstart to match the live path, so that docs are not a lie.
5. As a maintainer, I want `main` to carry `winmint.ps1` and the Worker’s `BOOTSTRAP_URL`, so that production points at the stable branch.
6. As a maintainer, I want tagging `v*` to upload `WinMint-<tag>.zip` + `.sha256`, so that bootstrap has assets.
7. As a maintainer, I want a cold verify after deploy, so that Gate B tooling is reachable without claiming wipe Primary.

## Implementation Decisions

- Binary toolkit zip from Releases (not source archive); layout already defined by pack script (Cli/Wizard win-arm64 SC, Provisioning AOT, servicing, samples, Justfile, metal).
- Worker proxies raw `winmint.ps1` from **main** (`BOOTSTRAP_URL`).
- Ephemeral temp session by default; durable cache only with explicit switches.
- Status stays honest: Gate B ≠ completed install; no bare-metal Primary claim in this cutover.
- Wrangler deploy is supported on Windows ARM64; use normal `wrangler deploy`.

## Testing Decisions

- Good test = external behavior of the Quickstart seam (bootstrap text, hash refuse, Wizard/Cli present, `just plan` from unpacked toolkit).
- Contract script already guards bootstrap strings; Release CI packs on tag.
- Cold verify: `irm https://winmint.yanai.sh` returns script; after a Release exists, `irm … | iex` opens Wizard with no git checkout.
- Do not require bare-metal wipe for this ticket.

## Out of Scope

- Bare-metal Primary / FirstLogon evidence
- Nix/devenv host story
- Mega progress / install host telemetry
- Closing or rewriting unrelated issues (e.g. historical Primary checklist issues) unless this cutover replaces them explicitly

## Further Notes

Local `dev` already contains pack/bootstrap/Worker/README/release workflow (uncommitted alongside other WIP). This ticket is the **ship sequence**, not a rewrite of that implementation.
