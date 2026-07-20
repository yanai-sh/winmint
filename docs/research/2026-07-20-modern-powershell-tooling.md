# Modern PowerShell / Windows DevOps tooling for WinMint (2026-07-20)

Which 2026-ecosystem PowerShell 7+ / Windows DevOps tools ought (or ought not) be adopted inside WinMint’s PowerShell scripts.

**Product constraints (from AGENTS.md):** Windows 11 ISO builder; PowerShell backend; `pwsh` 7.6.2+; subtractive ISO + FirstLogon agent; **no maintenance payload** left on installed systems; not a DSC / fleet configuration-management product.

**Method:** Decisions below use Microsoft Learn / first-party GitHub docs as primary sources. A secondary culture write-up was used only as a topic index and is not cited as authority.

---

## Inventory (WinMint today)

| Area | State |
|------|--------|
| PowerShell pin | `pwsh` 7.6.2+ (`AGENTS.md`, CI, `#Requires -Version 7.6`, PSScriptAnalyzer `TargetVersions = @('7.6')`) |
| winget | Heavy use: FirstLogon `Agent.Install.ps1` / `PackageManagers.ps1`; offline `Install-OfflineWinget` in image assets. **No** runtime `winget configure` |
| DSC / WinGet Configuration | Handoff-only: `Save-WinMintWingetConfigurationHandoff` in `Reports.ps1` (schema 0.2, `Microsoft.WinGet.DSC/WinGetPackage`); comment: not auto-run |
| Windows Terminal | Offline settings staging + FirstLogon profile finalization |
| Module install | **PSResourceGet:** `Install-PSResource` Pester (dev harness); `Save-PSResource` PwshSpectreConsole (host / interactive agent console) |
| PS 7 idioms | `ConvertFrom-Json -AsHashtable` rare; `ForEach-Object -Parallel`, `??`, `?.`, `$PSStyle` absent |
| Externals | DISM, oscdimg, reg, winget, Scoop, Hyper-V — no Sysinternals / jq / yq |
| Tests / lint | Pester ≥ 5.5.0; PSScriptAnalyzer via `Validate.ps1 -RunAnalyzer` (no version pin in v1 CI) |

---

## Decision matrix

| Candidate | Verdict | One-line fit |
|-----------|---------|--------------|
| PowerShell 7.6 LTS pin | **ALREADY USING** | Correct LTS baseline; keep |
| PSResourceGet (`Install-PSResource` / `Save-PSResource`) | **ADOPT** | Host/dev module cache only; replace `Save-Module` / `Install-Module` |
| `ConvertFrom-Json -AsHashtable` | **ADOPT** (opportunistic) | Prefer when mutating JSON configs (e.g. Terminal settings) |
| Null-coalescing `??`, null-conditional `?.` | **DEFER** | Nice readability; no product gap; adopt only in touched code |
| `ForEach-Object -Parallel` | **SKIP** (runtime) / **DEFER** (host downloads) | Setup/DISM/registry order-sensitive; parallel breaks sequencing |
| winget CLI | **ALREADY USING** | Core FirstLogon package path |
| `winget configure` / DSC v3 as runtime engine | **SKIP** | Conflicts with imperative agent + no-maintenance-payload |
| WinGet Configuration handoff YAML | **ALREADY USING** | Reviewable artifact only — keep non-executing |
| Windows Terminal | **ALREADY USING** | Staged settings + FirstLogon profiles |
| Scoop | **ALREADY USING** | Developer CLI bootstrap (policy already set) |
| Chocolatey | **SKIP** | Explicitly out of package-source policy |
| Sysinternals | **SKIP** (product) | Troubleshooting suite, not an install pipeline dependency |
| PSScriptAnalyzer | **ALREADY USING** | Keep; optionally pin version in CI later |
| Pester 5 | **ALREADY USING** | Keep ≥ 5.5; defer Pester 6 migration |
| PSReadLine / predictors | **SKIP** (product scripts) | Interactive shell UX only; ships with pwsh |
| Ansible / Intune / Az / Graph | **SKIP** | Fleet / cloud ops; not ISO builder scope |
| Windows Containers | **SKIP** | Unrelated packaging/runtime model |

---

## 1. PowerShell 7.6 LTS pin — ALREADY USING

**Claim:** PowerShell 7.6 is the current Long Term Servicing release (built on .NET 10), with end-of-support 14-Nov-2028. Current LTS patch line is 7.6.x (e.g. 7.6.3). PowerShell 7.5 is a Stable (non-LTS) line ending 10-Nov-2026.

**WinMint rationale:** The repo already requires 7.6.2+ and stages `pwsh` into the offline image. That is the right pin for an ISO builder whose setup scripts must stay supported for years. Do not chase 7.5-era marketing; stay on 7.6 LTS patches. Do not adopt 7.7 preview for product runtime.

Sources:

- [PowerShell Support Lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6)
- [What's New in PowerShell 7.6](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-76?view=powershell-7.6)
- [v7.6.3 Release (GitHub)](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.3)

---

## 2. PSResourceGet — ADOPT (host / tools only)

**Claim:** `Microsoft.PowerShell.PSResourceGet` is the supported gallery client (`Install-PSResource`, `Save-PSResource`, etc.). It combines Install/Save Module+Script from PowerShellGet v2. PowerShell 7.6.2 ships PSResourceGet v1.2.0 in the updated-modules list.

**WinMint rationale:** Product runtime must not leave gallery-installed modules as a maintenance surface on the target PC. But **host build console** (`Save-Module PwshSpectreConsole`) and **dev test bootstrap** (`Install-Module Pester`) should move to `Save-PSResource` / `Install-PSResource` so WinMint tracks the supported client. Prefer `Save-PSResource` into the existing dependency cache pattern (local path, then `Import-Module`) over machine-wide installs. Do not introduce PSResourceGet into FirstLogon agent package installs — those stay winget/Scoop.

Sources:

- [Microsoft.PowerShell.PSResourceGet module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/?view=powershellget-3.x)
- [Install-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/install-psresource?view=powershellget-3.x)
- [Save-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/save-psresource?view=powershellget-3.x)
- [What's New in PowerShell 7.6 — updated modules](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-76?view=powershell-7.6)

---

## 3. PowerShell 7 idioms — mixed

### 3a. `ConvertFrom-Json -AsHashtable` — ADOPT (opportunistic)

**Claim:** `-AsHashtable` (since PowerShell 6) returns a hashtable; from 7.3+ an `OrderedHashtable` that preserves key order. Useful for case-sensitive duplicate keys, empty-string keys, and faster hashtable-shaped edits.

**WinMint rationale:** Already used when editing Windows Terminal `settings.json`. Prefer `-AsHashtable` wherever scripts round-trip mutable JSON config (Terminal, status files) instead of PSCustomObject property surgery. No blanket rewrite required.

Source: [ConvertFrom-Json](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.6)

### 3b. Null-coalescing `??` / null-conditional `?.` — DEFER

**Claim:** These are language features of PowerShell 7.x (documented across PowerShell 7 what’s-new / about_Operators material). They are readability helpers, not new capabilities.

**WinMint rationale:** Absent today; no reliability gap. Use only when editing a function anyway — do not open a style-migration PR.

### 3c. `ForEach-Object -Parallel` — SKIP for setup/agent; DEFER for host-only I/O

**Claim:** `ForEach-Object` supports `-Parallel` / `-ThrottleLimit` in PowerShell 7+ for concurrent scriptblock work (runspace-based parallelization).

**WinMint rationale:** FirstLogon, SetupComplete, DISM offline servicing, registry tweaks, and autologon stamping are **order- and side-effect-sensitive**. Parallelizing them risks races (hive locks, winget contention, state.json corruption) for little gain. Only consider parallel on the **build host** for independent downloads/hash verifies, behind an explicit throttle — not as a default idiom.

Source: [ForEach-Object](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/foreach-object?view=powershell-7.6)

### 3d. `Microsoft.PowerShell.ThreadJob` rename — awareness only

**Claim:** In PowerShell 7.6, `ThreadJob` is replaced by `Microsoft.PowerShell.ThreadJob`; `Start-ThreadJob` cmdlet name is unchanged unless module-qualified.

**WinMint rationale:** No product dependency on ThreadJob today (PSSA excludes a related false positive). If host jobs are added later, use the new module name when qualifying.

Sources:

- [What's New in PowerShell 7.6 — Breaking Changes](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-76?view=powershell-7.6)
- [Cmdlet / module version history — ThreadJob](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/cmdlet-versions?view=powershell-7.6)

---

## 4. winget CLI — ALREADY USING

**Claim:** WinGet (`winget`) is the Windows Package Manager client (App Installer). Official install/upgrade/source/troubleshooting docs cover FirstLogon-class use. For broken clients, Learn documents `Microsoft.WinGet.Client` + `Repair-WinGetPackageManager`. WinGet CLI is not supported in SYSTEM/LocalSystem context.

**WinMint rationale:** Already the GUI/system package path (plus offline bundle staging). Keep imperative `winget install` / targeted upgrades. Continue best-effort repair + `winget source update` before catch-up installs. Ensure `Repair-WinGetPackageManager` is available when needed (module present), but do not replace the agent’s CLI install path with `Install-WinGetPackage` unless SYSTEM context forces it.

Sources:

- [Use WinGet to install and manage applications](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [Debugging and troubleshooting WinGet](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)
- [winget-cli README — Microsoft.WinGet.Client](https://github.com/microsoft/winget-cli/blob/master/README.md)

---

## 5. winget configure / DSC v3 — SKIP as runtime; handoff ALREADY USING

**Claim:** WinGet Configuration (`winget configure`) applies declarative YAML via PowerShell DSC resources (v2 schema / `Microsoft.WinGet.DSC/WinGetPackage`) or, on newer WinGet, DSC v3 processor documents. Microsoft DSC v3 (`dsc`) is a standalone CLI: no LCM service, JSON/YAML documents, invoked on demand — and is positioned for orchestration partners (WinGet, Dev Box, Azure Machine Configuration).

**WinMint rationale:** WinMint already **generates** a reviewable configuration handoff and correctly **does not auto-run** it. Adopting `winget configure` or `dsc config set` as the FirstLogon engine would (1) duplicate the agent’s transaction/state model, (2) pull Gallery DSC modules under `%LOCALAPPDATA%\Microsoft\WinGet\Configuration\Modules`, and (3) look like a configuration-management product — conflicting with “no maintenance payload” and the existing lock/progress contracts. Keep handoff YAML for humans/export; keep runtime imperative.

Sources:

- [WinGet Configuration overview](https://learn.microsoft.com/en-us/windows/package-manager/configuration/)
- [configure command (winget)](https://learn.microsoft.com/en-us/windows/package-manager/winget/configure)
- [Author a WinGet Configuration file](https://learn.microsoft.com/en-us/windows/package-manager/configuration/create)
- [WinGet Configuration file v3 schema](https://learn.microsoft.com/en-us/windows/package-manager/configuration/create-v3)
- [Microsoft DSC overview](https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-3.0)
- [PowerShell/DSC repository](https://github.com/PowerShell/DSC)

---

## 6. Windows Terminal — ALREADY USING

**Claim:** Windows Terminal is configured via `settings.json`; Microsoft documents profile settings (`commandline`, `startingDirectory`, etc.) and schema injection (`https://aka.ms/terminal-profiles-schema`) for validation.

**WinMint rationale:** Offline staging of Terminal settings + FirstLogon profile finalization (pwsh default, Cascadia, theme) already matches product stance. Continue treating Terminal as a **staged user experience**, not a DevOps control plane. No need for Terminal “features” beyond settings schema fidelity.

Sources:

- [Windows Terminal general profile settings](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-general)
- [Windows Terminal troubleshooting (settings.json / schema)](https://learn.microsoft.com/en-us/windows/terminal/troubleshooting)

---

## 7. Scoop — ALREADY USING; Chocolatey — SKIP

**Claim:** WinMint’s package-source policy (AGENTS.md) assigns winget/Store for GUI/system apps and Scoop for user-local developer CLIs. Chocolatey is listed among rejected peer package-source patterns in debloat strategy docs.

**WinMint rationale:** Keep Scoop bootstrap + MinGit/Starship/editor scoop paths. Do not add Chocolatey as a third package manager — it expands maintenance surface and duplicates winget for many GUI apps.

(No Microsoft primary source owns Scoop/Chocolatey product choices; decision is WinMint policy, not an ecosystem mandate.)

---

## 8. Sysinternals — SKIP (product dependency)

**Claim:** Sysinternals Suite is Microsoft’s troubleshooting utility bundle (Process Explorer, Handle, ProcMon, PsTools, etc.), available as ZIP / ARM64 ZIP / Store MSIX. It is for diagnose-and-fix workflows, not declarative install orchestration.

**WinMint rationale:** Do not stage Sysinternals into the ISO or FirstLogon agent. Maintainers may install the suite on the **build host** or use Live paths during VM debugging; that is out-of-band tooling, not WinMint runtime.

Sources:

- [Sysinternals](https://learn.microsoft.com/en-us/sysinternals/)
- [Sysinternals Suite](https://learn.microsoft.com/en-us/sysinternals/downloads/sysinternals-suite)

---

## 9. PSScriptAnalyzer — ALREADY USING

**Claim:** PSScriptAnalyzer is Microsoft’s static checker for PowerShell; install via `Install-PSResource` or `Install-Module`; settings files select include/exclude rules and compatibility targets.

**WinMint rationale:** Already gated via `Validate.ps1 -RunAnalyzer` and `PSScriptAnalyzerSettings.psd1` (`PSUseCompatibleSyntax` → 7.6). Keep. Optional later polish: pin a minimum analyzer version in CI (today unpinned) and prefer `Install-PSResource` when bootstrapping the tool — not a product-runtime change.

Sources:

- [PSScriptAnalyzer overview](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules)
- [Using PSScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules)
- [PowerShell/PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)

---

## 10. Pester 5 — ALREADY USING; Pester 6 — DEFER

**Claim:** Pester is the de facto PowerShell test framework. Project docs: install with gallery client, `*.Tests.ps1`, `Invoke-Pester`. Upstream: Pester 5 entered maintenance mode after Pester 6; Pester 6 targets newer assertion syntax / experimental parallel runner.

**WinMint rationale:** Contract harness already requires Pester ≥ 5.5.0. Stay on Pester 5 until a deliberate migration ticket (v6 assertion changes are not free). Do not use Pester as a guest configuration engine — guest inspect already wraps focused acceptance checks.

Sources:

- [Pester quick start](https://pester.dev/docs/quick-start)
- [pester/Pester (GitHub)](https://github.com/pester/Pester)

---

## 11. PSReadLine / predictors — SKIP (product scripts)

**Claim:** PSReadLine ships with PowerShell 7.x (7.6.2 lists PSReadLine v2.4.5 among updated modules) and improves interactive editing / prediction. It is a console host feature, not a scripting API for offline servicing.

**WinMint rationale:** FirstLogon runs under a provisioning lock with a native splash — not an interactive PSReadLine session. Do not configure predictors, Az predictors, or Copilot CLI integrations as product work.

Source: [What's New in PowerShell 7.6 — updated modules](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-76?view=powershell-7.6)

---

## 12. Ansible / Intune / Az PowerShell / Microsoft Graph — SKIP

**Claim:** These are fleet, cloud, and identity management surfaces (Microsoft Endpoint / Intune, Azure Az modules, Graph SDK, Ansible Windows collections). DSC overview explicitly lists higher-order orchestrators (WinGet, Dev Box, Azure Machine Configuration) as DSC partners — enterprise CM, not ISO builders.

**WinMint rationale:** WinMint ends at FirstLogon completion + restore point. No Azure subscription, MDM enrollment, or Ansible control node belongs in `src/runtime/`. Adding Az/Graph modules would bloat the image and contradict “no maintenance payload.”

Source (DSC partner framing only): [Microsoft DSC overview — Integrating with DSC](https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-3.0)

---

## 13. Windows Containers — SKIP

**Claim:** Windows container images / Server container hosts are a separate packaging and runtime model from offline WIM servicing + unattended Setup.

**WinMint rationale:** Product delivers a bootable ISO for Hyper-V / bare metal, not a container image. Do not adopt Windows Containers tooling inside the engine.

---

## Surprises (ahead / behind)

**Ahead of a typical 2026 “PowerShell DevOps” checklist**

- Already on **PowerShell 7.6 LTS** (not stuck on 5.1 or 7.5 Stable).
- Offline **winget** provisioning + FirstLogon repair/source-update path.
- Full **Windows Terminal** settings staging (not “install Terminal and hope”).
- Generates WinGet Configuration YAML as a **handoff** while refusing to become a DSC runner — correct product boundary.
- Host UX already uses **PwshSpectreConsole**; CI already has **Pester + PSScriptAnalyzer**.

**Behind (intentional / cosmetic)**

- Modern null idioms (`??` / `?.`) remain underused — adopt only in touched code.
- No `ForEach-Object -Parallel` — **intentional gap** for runtime safety, not lag.

---

## Implemented (2026-07-20)

1. Host Spectre cache + interactive agent console + Pester bootstrap use `Save-PSResource` / `Install-PSResource`.
2. `Read-WinMintJsonFile -AsHashtable`; Terminal settings reads prefer `-AsHashtable` where touched.
3. Still **do not** wire `winget configure`, DSC v3, Sysinternals, Chocolatey, Az/Graph, Ansible, or Containers into runtime.
