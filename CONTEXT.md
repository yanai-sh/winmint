# WinMint

Workstation state compiler — debloat, policies, packages, DMA settle, and account intent from a **Profile**. Delivery artifact: bootable USB/ISO. User always supplies official Microsoft **Source ISO**.

Policy / acceptance: [DESIGN](docs/DESIGN.md).

## Language

**Source ISO** — Official Microsoft install media the user provides. No silent Windows download.  
_Avoid_: golden ISO, UUP default source

**Profile** — Build intent for one ISO (`winmint.profile/v1`).  
_Avoid_: BuildConfig (user-facing); preset names in JSON

**Orchestrator** — Validates Profile, plans, drives elevated Servicing. Hosts: Cli + Avalonia Wizard (**BuildPlan**).  
_Avoid_: second planning brain in Cli/Wizard

**BuildPlan** — Profile + run options → plan artifacts.  
_Avoid_: DISM at the flag layer; ports before a second adapter

**Servicing / ImageServicing** — Offline WIM/ISO work via elevated `pwsh -File` kernels.  
_Avoid_: in-process DISM from Wizard; guest FirstLogon Servicing

**Payload** — Staged SetupComplete, Supervisor, jobs/media. `%WINDIR%\WinMint\` tenure-only; `%ProgramData%\WinMint\` may remain for evidence.  
_Avoid_: guest pwsh control plane; dual `$OEM$` SetupScripts

**Machine setup** — Supervisor `--machine-setup`: autologon + fail-closed Shell verify. No splash/settle/jobs.  
_Avoid_: calling this FirstLogon

**Provisioning Supervisor / ProvisioningSession** — One AOT process: Shell tenure, splash, DMA settle, jobs, reboot checkpoint, fail-open.  
_Avoid_: peer Splash.exe; guest pwsh product runtime; file mailbox control plane

**Splash** — In-process Direct2D/GDI presenter.  
_Avoid_: Splash.exe peer; Avalonia/WinUI on the ISO

**FirstLogon** — Supervisor as Shell → splash → DMA settle → jobs.  
_Avoid_: conflating with Machine setup

**Provisioning lock** — Supervisor is Shell + splash; unlock = `explorer.exe` + exit.

**Provisioning jobs / metal jobs** — Post hard-settle installs (per-id or batch). Same executor Smoke and metal.  
_Avoid_: jobs before hard settle

**DMA interop / settle** — Ireland during Setup; restore user region by **final snapshot**. Hard: locale/GeoID/TZ. Soft: location.  
_Avoid_: sticky intermediate failures as authoritative

**Smoke** — Hyper-V plumbing acceptance (`Test` lane, Local+autoLogon, Pro).  
_Avoid_: treating Smoke alone as Primary wipe confidence

**Primary gate** — Release `samples/sl7.profile.json` safe to wipe primary SL7. Details: [DESIGN](docs/DESIGN.md#acceptance).  
_Avoid_: shipping recovery images

**Image quality** — Run override `Test` | `Release` (not Profile).

**Install engine** — WinPE apply only (no Setup `/legacy`).

**Debloat venue / Keep-flag** — AppX online by default; caps/features offline when listed; remove-list polarity; host **`recommended`** expands → ids; CDM not primary.  
_Avoid_: presets-in-JSON; CDM-as-primary

**Wizard** — Avalonia BuildPlan host: Source → Account → Software → Review; Phase B elevated Apply.
_Avoid_: DISM or second planner in UI

**Package catalog** — `config/packages.json`: chip key ≠ Profile install id.  
_Avoid_: live winget search in Wizard
