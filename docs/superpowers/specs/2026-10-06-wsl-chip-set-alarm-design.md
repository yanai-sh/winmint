# WSL chip set + Arch via ALARM

**Date:** 2026-10-06 · **Status:** accepted · **Branch context:** station UX / catalog honesty

Brainstorming artifact for one catalog/chip change. Behaviour after land lives in `config/packages.json` + `CuratedPackageChips` + tests — not this file.

## Choice

Wizard WSL chips are exactly four:

| Chip label | Profile / catalog token | Install | Architectures |
|------------|-------------------------|---------|-----------------|
| Fedora | `FedoraLinux` | official `wsl --install` (catalog `store`) | amd64, arm64 |
| Ubuntu | `Ubuntu` | official `wsl --install` | amd64, arm64 |
| NixOS | `NixOS-WSL` | `fromFile` `nix-community/NixOS-WSL` | amd64, arm64 |
| Arch | new/retargeted token (e.g. `archlinuxarm-wsl`) | `fromFile` `artiga033/archlinuxarm-wsl` | **arm64 only** |

- Comfort / `CuratedDefaults.WslTokens` stays **`FedoraLinux`** (not Arch).
- Arch chip installs **Arch Linux ARM** community images (`archlinuxarm-aarch64*` on latest GitHub release), not official `archlinux`.
- On amd64 images the Arch chip is omitted or disabled; plan already fail-closes unsupported arch.

## Rejected

- Official `archlinux` as chip or arm64 catalog entry (Microsoft manifest has no `Arm64Url`; Arch maintainers defer until official aarch64).
- yuk7/ArchWSL as the Arch path (x64-only community predecessor).
- Dual-token Arch chip (official amd64 + ALARM arm64 behind one UI key).
- Making ALARM the Comfort default.
- Keeping Pengwin on the chip row (paid Store niche).
- Expanding chips to Debian / openSUSE / Alma / Rocky / Kali / Gentoo / Alpine without a concrete ask.

## Implementation notes (not law)

- Drop `pengwin` and store `archlinux` from catalog + `CuratedPackageChips.Wsl`.
- ALARM assets: candidate substring `archlinuxarm-aarch64`; prefer asset names ending in `.wsl` over `.wsl.bundle` / `.SHA256` if the downloader’s `Contains` order is ambiguous.
- `installId` / registered distro name: something stable like `ArchLinuxARM` (confirm against image OOBE / wiki).
- Tests: mirror NixOS fromFile coverage; amd64 plan rejects Arch token; Fedora remains curated default.
- No CONTEXT/ADR required unless a coined polarity changes; chip keys remain UI vocabulary (ADR-010).

## Success

- Arm64 Comfort seed still plans Fedora only.
- Selecting Arch on arm64 plans a `fromFile` job for `artiga033/archlinuxarm-wsl`.
- Selecting Arch on amd64 cannot plan successfully.
- Wizard shows only Fedora, Ubuntu, NixOS, Arch.
