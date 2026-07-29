<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

ARM64-first Windows 11 ISO builder for clean developer workstation installs.
You supply the official Microsoft ISO — WinMint does not download or redistribute Windows ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)).

**Status:** M1 in progress — ticket **01** (`validate` / `plan`) landed; imaging starts at **02**.

## Quickstart

Requires .NET 11 preview SDK (see `global.json`) and `pwsh` 7.6+ on the host.

```powershell
dotnet run --project src/WinMint.Cli -- validate samples/smoke.profile.json
dotnet run --project src/WinMint.Cli -- plan samples/smoke.profile.json --out .scratch/plan
```

[Design](docs/DESIGN.md) · [Architecture](docs/ARCHITECTURE.md) · [Tickets](docs/TICKETS.md) · [Issues](https://github.com/yanai-sh/winmint/issues) · [Agents](AGENTS.md)

[GPL-3.0-or-later](LICENSE)
