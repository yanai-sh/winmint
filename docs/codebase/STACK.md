# Technology Stack

Snapshot note: updated 2026-07-07. Onboarding/audit snapshot — see [docs/decisions/DECISIONS.md](../decisions/DECISIONS.md) for verdicts.

## Runtime summary

| Area | Value | Evidence |
|------|-------|----------|
| Build engine | PowerShell 7.6.2+ | `src/runtime/image/WinMint.ps1`, DISM/WIM |
| Build wizard UI | C# WebView2 + HTML/JS | `apps/setup-shell-web/`, `wizard.html` |
| FirstLogon splash | C# .NET 10 AOT + Direct2D (Vortice) | `apps/setup-shell/` → `WinMintSetupShell.Native.exe` |
| Bootstrap CDN | JavaScript (ES module) | `cloudflare/winmint/` |
| Host OS | Windows 11, Administrator for real builds | `README.md`, `config/release-readiness.json` |

## Production dependencies

| Dependency | Role |
|------------|------|
| PowerShell 7.6.2+ | Engine, setup, agent, validation |
| DISM / oscdimg (ADK) | Offline image servicing, ISO output |
| Vortice.Direct2D1 | Native splash rendering |
| Microsoft.Web.WebView2 | Build wizard host |
| JSON Schema | BuildProfile, Manifest, agent/runtime contracts |

PowerShell engine has no external gallery modules beyond Windows tooling.

## Development toolchain

| Tool | Purpose |
|------|---------|
| PSScriptAnalyzer | PowerShell lint (`Validate.ps1 -RunAnalyzer`) |
| Pester 5 | Contract tests (`Invoke-WinMintPesterContract.ps1`) |
| `dotnet publish` | `Build-WinMintSetupShell.ps1` (native AOT + WebView2) |
| GitHub Actions | CI: setup-shell publish + validate (no Hyper-V) |
| Hyper-V VM scripts | Manual smoke (`docs/VM-Acceptance.md`) |

## Key commands

```powershell
pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer
pwsh -NoProfile -File tools\dev\Invoke-WinMintPesterContract.ps1
pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1 -AllArch
pwsh -NoProfile -File WinMint-GUI.ps1
pwsh -NoProfile -File tools\dev\Show-WinMintSplash.ps1
```

## Dual setup-shell binaries

| Binary | Source | Use |
|--------|--------|-----|
| `WinMintSetupShell.exe` | `apps/setup-shell-web` | Wizard (`--wizard`), `WinMint-GUI.ps1` |
| `WinMintSetupShell.Native.exe` | `apps/setup-shell` | ISO FirstLogon splash (staged as `setup-shell\WinMintSetupShell.exe`) |

See [ADR-002](../decisions/ADR-002-dual-setup-shell-hosts.md).
