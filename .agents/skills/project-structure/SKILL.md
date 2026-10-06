---
name: project-structure
description: WinMint solution layout — where projects live, pins, and what not to invent (no Core/Infrastructure split, no CPM). Use when adding a project, renaming modules, or proposing solution structure.
---

# WinMint project structure

Authority: [AGENTS.md](../../../AGENTS.md) map + [ADR-004](../../../docs/decisions/ADR-004-stack-and-guest-control-plane.md). Behaviour lives in `src/` / `servicing/` / `tests/` — not a living design overlay ([ADR-014](../../../docs/decisions/ADR-014-docs-are-not-living-law.md)).

## Layout

```
WinMint.slnx
global.json                          # SDK pin (net11 preview)
Directory.Build.props                # shared TFM / analyzers / warnings
src/
  WinMint.Contracts/                 # job wire / shared types (Brain — no PackageReferences)
  WinMint.Orchestrator/              # HostCompile, BuildPlan, ImageServicing ports
  WinMint.Cli/                       # thin host adapter
  WinMint.Wizard/                    # Avalonia host adapter
  WinMint.Provisioning/              # AOT Supervisor (ISO / guest)
  WinMint.WinPeApply/                # WinPE apply helper
servicing/                           # elevated pwsh kernels (one opcode each)
config/                              # packages.json (+ packages.proof.json)
payload/                             # guest payload / skel / desktop assets
samples/                             # profiles
tools/{host,vm,apply}/               # host recipes, Smoke, Host Apply
tests/
  WinMint.Tests/                     # xUnit v3 + MTP
  contract/                          # Test-*.ps1 (no live ISO / no Hyper-V)
  fixtures/                          # maintainer-host.json, …
```

## Pins

- TFM `net11.0` (+ Windows TFMs where Win32/Avalonia need them) — see `Directory.Build.props` / each `.csproj`
- SDK: `global.json`
- Gate: `just check`
- **No** `Directory.Packages.props` / Central Package Management (rejected in ADR-004)

## Do

- Add code under the existing concern in the map; front ends stay thin over HostCompile
- Prefer BCL / inbox platform APIs; every new `PackageReference` needs one sentence “why not BCL?”
- Keep Servicing as `servicing/*.ps1` kernels; elevate only those

## Don’t

- Invent `Core` / `Api` / `Infrastructure` / Clean Architecture folders
- Add MediatR, Generic Host, or a DI-container backbone
- Introduce CPM or a living deps allowlist markdown
- Put a second planning brain in Cli/Wizard
- Commit session-plan overlays as product law (`docs/superpowers/`, DESIGN.md, ARCHITECTURE.md)
