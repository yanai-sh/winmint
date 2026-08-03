<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

ARM64-first Windows 11 ISO builder for clean developer workstation installs.
You supply the official Microsoft ISO — WinMint does not download or redistribute Windows ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)).

**Status:** M1 in progress — tickets **01**–**03** landed; next is **04** (Shell splash; needs splash spike appendix).

## Quickstart

Requires .NET 11 preview SDK (see `global.json`) and `pwsh` 7.6+ on the host.

```powershell
dotnet run --project src/WinMint.Cli -- validate samples/smoke.profile.json
dotnet run --project src/WinMint.Cli -- plan samples/smoke.profile.json --out .scratch/plan
# build/apply need a Source ISO + workdir (elevates once via servicing/RunPlan.ps1):
# dotnet run --project src/WinMint.Cli -- build samples/smoke.profile.json --iso path\to\source.iso --work .scratch/work
```

## Testing loops

- **Daily:** `just check` — unit tests + fake elevated runner; no ISO/DISM.
- **Maintainer Apply** (multi-hour DISM): `just publish-provisioning`, then `just apply-maintainer path\to\source.iso .scratch/work`. After a successful cold run, the recipe passes `--reuse-media` when `.scratch/work/media/sources/.winmint-single-index` exists (skips ISO copy + single-image export).
- **Watch progress:** `Get-Content .scratch\work\apply-status.txt -Wait` (`STALL_SUSPECT` is advisory only).
- **Optional:** `just exclude-scratch` (admin) adds Defender exclusions for `.scratch` to speed commits.

[Design](docs/DESIGN.md) · [Architecture](docs/ARCHITECTURE.md) · [Tickets](docs/TICKETS.md) · [Issues](https://github.com/yanai-sh/winmint/issues) · [Agents](AGENTS.md)

[GPL-3.0-or-later](LICENSE)
