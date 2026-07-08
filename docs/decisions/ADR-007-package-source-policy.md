# ADR-007: Fixed package source policy

**Status:** Accepted  
**Date:** 2026-07-07

### Context

FirstLogon installs editors, shell layers, WSL distros, and CLI tooling. Users could choose package managers or sources per app.

### Decision

WinMint decides sources: **winget** for GUI/signed installers, **Scoop** for user-local CLI plumbing (MinGit, Starship, Neovim), **Store** where upstream distributes via Microsoft Store, **pinned direct download** only for documented exceptions (e.g. ARM64 Everything for Raycast).

Users choose *what* to install via profile; not *how* packages are fetched.

### Consequences

Agent modules implement the policy table in AGENTS.md; profile does not expose source pickers.

### Review trigger

New package class that no catalog source can satisfy.
