# ADR-001: GPUI/Rust GUI → WebView2 wizard

**Status:** Accepted  
**Date:** 2026-07-07  
**Supersedes:** GPUI/Rust `apps/gui/` architecture (deleted)

### Context

WinMint needed a desktop UI for profile authoring and build invocation. An initial implementation used GPUI (Rust, retained-mode) with a PowerShell bridge for engine calls.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| GPUI/Rust native GUI | Fast native UI, shared patterns with Zed ecosystem | Second language toolchain, bridge duplication, slow iteration on wizard screens |
| WebView2 + HTML/JS wizard | Rapid UI iteration, matches setup-shell asset folder, single bridge pattern | WebView2 runtime on build host only |
| WinForms/WPF full native | Familiar .NET | Heavy wizard UI in XAML/code-behind |

### Decision

Remove GPUI/Rust GUI (`apps/gui/`, `Cargo.toml`, `tools/gui/`). Ship the build wizard as **WebView2 + HTML/JS** hosted by `apps/setup-shell-web/` (`WinMintSetupShell.exe` with `--wizard`). PowerShell engine work stays in `tools/ui-bridge/`.

### Consequences

- **Positive:** One UI asset pipeline (`wizard.html/js/css`); no Cargo in CI; faster wizard changes.
- **Negative:** WebView2 runtime required on machines running `WinMint-GUI.ps1` / `winmint.ps1` GUI mode.
- **Follow-up:** Track 1 purges GPUI references from docs/tests; Track 0 wires dual publish for wizard exe.

### Review trigger

If WebView2 dependency becomes unacceptable on build hosts, revisit Tauri/WinUI — not GPUI resurrection without new ADR.
