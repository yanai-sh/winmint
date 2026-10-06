# Cross-boundary package IDs in Contracts

**Date:** 2026-10-06 · **Status:** accepted (streamlined) · **Branch context:** DRY winget identity across Orchestrator ↔ Provisioning

Brainstorming artifact. Behaviour after land lives in `src/WinMint.Contracts`, call sites, and tests — not this file.

## Choice

Identity that both Orchestrator and Provisioning compare against lives once in Contracts as a flat static class:

```csharp
public static class PackageIds
{
    public const string Yasb = "AmN.yasb";
    public const string Komorebi = "LGUG2Z.komorebi";
    public const string Cursor = "Anysphere.Cursor";
    public const string ZenBrowser = "Zen-Team.Zen-Browser";
}
```

- **Contracts** owns those four winget install IDs only (the current cross-project duplicates).
- **ProductPosture** keeps composition (always-on lists, AppX, DoH, merge/union). Its Yasb/Komorebi constants become `PackageIds.*` references (or call sites switch and the ProductPosture duplicates are deleted).
- **ShellDesktopLayout** / **ShellChromeLayout** delete local winget ID consts; use `PackageIds`.
- **Chip keys and taskbar surface tokens** stay in Orchestrator (`StationOutcomes`, chip inject sites). Wizard already references Orchestrator — do not put chip keys or `"YASB + tHide"` in Contracts. Collapse Wizard’s duplicate `YasbTaskbar` onto `StationOutcomes.TaskbarYasb`.
- **One catalog sync test:** `PackageIds.*` (and ProductPosture always-on winget IDs) resolve via `PackageCatalog.Default`.
- **Surface token ≠ chip key:** keep `StationOutcomes.TaskbarYasb` / package chip `"yasb"` as separate consts even if the string value matches today.

## Rejected

- A wide `ManagedPrograms` bag for every WinMint-touched program (Brave, MinGit, scoop toolbox, …) in Contracts — Orchestrator-only; no Provisioning consumer.
- Nested per-program types (`ManagedPrograms.Yasb.WingetId`) — ceremony for four flat IDs.
- Chip keys / surface labels / `thide.exe` in Contracts — not cross-boundary identity.
- Codegen from `packages.json` — overkill; tHide is not in the catalog.
- Aliasing taskbar surface to package chip key — freezes a coincidence (ADR-015 axes stay independent).
- Moving ProductPosture composition (always-on lists, AppX, DoH) into Contracts.

## Implementation notes (not law)

- Add `src/WinMint.Contracts/PackageIds.cs`.
- Rewire ProductPosture Yasb/Komorebi; delete ShellDesktopLayout / ShellChromeLayout winget ID consts.
- Orchestrator-local: chip key consts for yasb/komorebi/whkd injects in `ChipAxisResolve` / Software stage; Wizard uses `StationOutcomes.TaskbarYasb`.
- Tests: prefer `PackageIds.*` where asserting those four IDs; add catalog sync coverage.
- Gate: `just check`.
- No CONTEXT/ADR unless polarity changes; this is a locality refactor.

## Success

- No duplicated winget ID string literals for Yasb / Komorebi / Cursor / Zen across Orchestrator and Provisioning.
- Provisioning does not gain an Orchestrator project reference.
- Catalog sync test fails if a `PackageIds` constant drifts from `packages.json`.
