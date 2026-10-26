# ADR-020: Post-install workflow is stock install, Live posture, then dotfiles

**Status:** Accepted · **Date:** 2026-10-26  
**Clarifies:** [ADR-018](ADR-018-maintainer-only-until-usable.md) (Live posture is the operator path)

### Context

No WinMint-built USB has booted the SL7 yet. Until a WinMint USB install is proven on real Secure Boot hardware, the maintainer installs Windows from stock Microsoft media and finishes the machine afterwards.

The maintainer's default developer environment spans Windows 11 ARM64 (SL7), Fedora 44 under WSL2, and bare-metal Fedora 44. The plan splits it into four layers. Layer 0 is the host OS: drivers, AppX strip, OneDrive, and policy. Layer 1 is user dotfiles and XDG paths through chezmoi. Layer 2 is global toolchains through `mise` and `uv`. Layer 3 is per-project isolation through `uv`, `.mise.toml`, and `devenv`.

On the ISO path, FirstLogon also places `payload/shell-skel`, `payload/desktop`, and `payload/fonts`, and installs packages and the WSL platform. A stock install with Live posture gets none of that.

### Rejected

- Growing Live posture into a second FirstLogon: package installs, skel, desktop surfaces, fonts, or WSL from `post-install/`.
- Copying `post-install/` into the dotfiles repository. A second copy drifts from the scripts this tree tests and edits.
- Running `Set-ExplorerView`, `Set-QuietTaskbar`, and `Disable-EdgePromotions` unelevated as "HKCU-only". Every Live posture script requires elevation, and those scripts also write HKLM.
- Running `Install-SurfaceDrivers.ps1` whenever it is present. Drivers stay opt-in through `-Drivers`.
- Putting chezmoi, XDG, `mise`, `uv`, or Nix in this repository, in a Profile, or in FirstLogon jobs.
- Pixi / conda-forge as a toolchain source.

### Decision

Until a WinMint USB install is proven, the post-install workflow runs in this order:

1. Install from stock Microsoft media.
2. Run Windows Update.
3. Run Live posture.
4. Run the dotfiles bootstrap.
5. Install WSL and the Fedora distro.

WinMint owns **Layer 0 only**, and only through **Live posture**. The dotfiles repository (chezmoi) owns Layers 1–3, the WSL step, and the runbooks for them.

The dotfiles bootstrap fetches `post-install/` from a pinned WinMint ref and runs `Apply-LivePosture.ps1` (plus `-Drivers` when wanted) in one elevated process. It does not call individual scripts with its own privilege split.

On a post-install machine, dotfiles is the source of truth for the user-layer files that `payload/` carries for the ISO: pwsh profile, Terminal settings, starship, komorebi/YASB, and the Nerd Font. `payload/` keeps its copies for the ISO goal. A change to one is not mirrored into the other until the ISO path is usable again.

WinMint does not write `/etc/wsl.conf` or `.wslconfig` ([research](../research/2026-08-09-wslconfig-modern.md)).

The dotfiles Windows package list must cover what `just check` needs on the Host: pwsh 7.6+, the .NET SDK pinned in `global.json`, and `just`. It also needs full Git for Windows, not MinGit, because Cursor CLI agent workers need Git Bash. Smoke also needs Hyper-V. These packages must have native ARM64 builds.

### Review trigger

A WinMint USB install passes on the SL7, so Layer 0 and the payload assets move back to the install path. Or the dotfiles bootstrap needs Layer 0 behaviour that Live posture does not expose.
