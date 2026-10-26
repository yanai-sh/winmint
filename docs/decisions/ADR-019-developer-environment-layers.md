# ADR-019: Developer environment is dotfiles over Live posture

**Status:** Accepted · **Date:** 2026-10-26  
**Clarifies:** [ADR-018](ADR-018-maintainer-only-until-usable.md) (Live posture is the operator path)

### Context

The maintainer's default developer environment spans Windows 11 ARM64 (SL7), Fedora 44 under WSL2, and bare-metal Fedora 44. The plan splits it into four layers. Layer 0 is the host OS: drivers, AppX strip, OneDrive, and policy. Layer 1 is user dotfiles and XDG paths through chezmoi. Layer 2 is global toolchains through `mise` and `uv`. Layer 3 is per-project isolation through `uv`, `.mise.toml`, and `devenv`. The plan "ports" `post-install/` into a separate chezmoi repository.

### Rejected

- Copying `post-install/` into the dotfiles repository. A second copy drifts from the scripts this tree tests and edits.
- Running `Set-ExplorerView`, `Set-QuietTaskbar`, and `Disable-EdgePromotions` unelevated as "HKCU-only". Every Live posture script requires elevation, and those scripts also write HKLM.
- Running `Install-SurfaceDrivers.ps1` whenever it is present. Drivers stay opt-in through `-Drivers`.
- Putting chezmoi, XDG, `mise`, `uv`, or Nix in this repository, in a Profile, or in FirstLogon jobs.
- Pixi / conda-forge as a toolchain source.

### Decision

WinMint owns **Layer 0 only**, and only through **Live posture**. The dotfiles repository (chezmoi) owns Layers 1–3 and the runbooks for them.

The dotfiles Windows bootstrap installs user tools first. It then fetches `post-install/` from a pinned WinMint ref and runs `Apply-LivePosture.ps1` (plus `-Drivers` when wanted) in one elevated process. It does not call individual scripts with its own privilege split.

WinMint does not write `/etc/wsl.conf` or `.wslconfig` from Live posture ([research](../research/2026-08-09-wslconfig-modern.md)). Enabling WSL and installing distros stays in the dotfiles runbook. The product's FirstLogon WSL job is separate.

The dotfiles Windows package list must cover what `just check` needs on the Host: pwsh 7.6+, the .NET SDK pinned in `global.json`, and `just`. Smoke also needs Hyper-V. These packages must have native ARM64 builds.

### Review trigger

A portable Output ISO becomes usable, so Layer 0 moves from Live posture to the ISO. Or the dotfiles bootstrap needs Layer 0 behaviour that Live posture does not expose.
