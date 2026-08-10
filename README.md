<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

ARM64-first Windows 11 ISO builder for clean developer workstation installs.
You supply the official Microsoft ISO — WinMint does not download or redistribute Windows ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)).

**Status**

- Debloated default: host preset **`recommended`** (zero-config curated remove-lists)
- Smoke: **Proven** (Hyper-V real Source ISO)
- Wizard / metal jobs / caps-features: **Built** (`just check`)
- Primary gate: maintainer-timed ([DESIGN](docs/DESIGN.md#acceptance))
- Alpha — next work is maintainer pick ([Issues](https://github.com/yanai-sh/winmint/issues))

## Quickstart

Requires .NET 11 preview SDK (see `global.json`) and `pwsh` 7.6+ on the host.

**Before you wipe a machine** with a WinMint ISO: have a restore path for *that* PC — OEM recovery when the vendor provides it (Surface: [recovery image download](https://support.microsoft.com/surfacerecoveryimage), serial + Microsoft account), or a Windows recovery drive. WinMint does not download or ship recovery images.

```powershell
dotnet run --project src/WinMint.Cli -- validate samples/smoke.profile.json
dotnet run --project src/WinMint.Cli -- plan samples/smoke.profile.json --out .scratch/plan
# build needs a Source ISO + workdir (elevates once via servicing/RunPlan.ps1):
# dotnet run --project src/WinMint.Cli -- build samples/smoke.profile.json --iso path\to\source.iso --work .scratch/work
```

## Testing loops

- **Daily:** `just check` — unit tests + fake elevated runner; no ISO/DISM.
- **Maintainer Apply** (multi-hour DISM): `just publish-provisioning`, then `just apply-maintainer path\to\source.iso .scratch/work`. After a successful cold run, the recipe passes `--reuse-media` when `.scratch/work/media/sources/.winmint-single-index` exists (skips ISO copy + single-image export).
- **Watch progress:** `just watch-apply WORK=.scratch/work` (or `Get-Content .scratch\work\apply-status.txt -Wait`). Status lines: `stage=opcode|done|failed:*` · `updated=` · `log=workdir\logs\NN-Opcode.log`. `STALL_SUSPECT` is Smoke VM only (`tools/vm`), not Apply.
- **Optional:** `just exclude-scratch` (admin) adds Defender exclusions for `.scratch` to speed commits.
- **Disk hygiene:** `output/` + `.scratch/` + `*.iso`/`*.wim`/`*.esd`/`*.vhdx`/`*.avhdx` are gitignored. DISM mounts live under `%ProgramData%\WinMint\Servicing\` (not `.scratch`). Failed Apply discards leftover mounts (workdir/logs kept). After Apply/Smoke campaigns: `just clean-artifacts` (keeps 1 newest heavy workdir + 2 newest ISOs under `.scratch`) or `just wipe-scratch` to empty `.scratch` entirely. Do not run during Apply/Smoke.

[Design](docs/DESIGN.md) · [Architecture](docs/ARCHITECTURE.md) · [Agents](AGENTS.md) · [Issues](https://github.com/yanai-sh/winmint/issues)

[GPL-3.0-or-later](LICENSE)
