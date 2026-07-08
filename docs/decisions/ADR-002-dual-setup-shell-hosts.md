# ADR-002: Dual setup-shell hosts

**Status:** Accepted  
**Date:** 2026-07-07

### Context

WinMint needs two presentation moments: (1) **pre-build wizard** on the developer machine, (2) **fullscreen provisioning splash** on the installed system during FirstLogon. Constraints differ: ISO payload size, WebView2 availability, and fullscreen desktop guard on a live user session.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| Single WebView2 host for both | One codebase | WebView2 on ISO/first boot; larger binary |
| Single Direct2D native host for both | Small ISO binary | Poor wizard ergonomics; no HTML forms |
| **Dual hosts** | Right tool per phase | Two publish targets, explicit naming required |

### Decision

Publish two executables per architecture under `assets/runtime/setup/setup-shell/bin/{arch}/`:

- `WinMintSetupShell.exe` — WebView2 WinForms (`apps/setup-shell-web/`), wizard mode (`--wizard`)
- `WinMintSetupShell.Native.exe` — .NET AOT Direct2D (`apps/setup-shell/`), ISO FirstLogon splash

ISO staging copies **Native** only. `WinMint-GUI.ps1` and `winmint.ps1` launch the WebView2 binary.

Reject MB file-size heuristics to distinguish binaries.

### Consequences

- **Positive:** Lean ISO; rich wizard; clear contracts.
- **Negative:** Two C# projects to maintain; shared Win32 guard code should be linked or shared.
- **Follow-up:** Track 0 implements dual publish and path-based resolution.

### Review trigger

If WebView2 becomes reliably preinstalled and small enough for ISO, reconsider single host — unlikely near-term.
