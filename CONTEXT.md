# WinMint

Workstation state compiler — debloat posture, policies, packages, DMA settle, and account intent compiled from a **Profile**. Bootable USB/ISO is the default delivery artifact; the user always supplies official Microsoft **Source ISO** media.

## Language

**Source ISO**:
Official Microsoft Windows installation media that the user always provides. WinMint does not bundle, pin, or silently download Windows images — required for legal and product reasons.
_Avoid_: golden ISO, shipped ISO, UUP default source

**Profile**:
The user’s build intent for one ISO — the input contract the orchestrator validates and turns into servicing and payload work. Schema is clean-sheet (not WinMint v1 BuildProfile v4).
_Avoid_: uiintent, BuildConfig (as a user-facing name)

**Orchestrator**:
The typed headless brain that validates the Profile, plans the build, and drives elevated servicing and payload staging. Public surface is the C# CLI; the wizard is a later client of the same brain. Deep module interface: **BuildPlan** (Profile + run options → plan artifacts).
_Avoid_: ui-bridge, engine (when meaning the old PowerShell monolith); a second planning brain inside Cli

**BuildPlan**:
The Orchestrator’s deep module: small interface that turns a Profile (and run overrides such as image quality) into unattend, job JSON, stage list, and related plan artifacts. Cli and Wizard are hosts of BuildPlan, not owners of plan logic.
_Avoid_: exposing schema/DISM details at the Cli flag layer; inventing ports before a second adapter exists

**Servicing**:
Offline image work on the WIM/ISO (mount, package/hive changes, export). Executed by elevated PowerShell kernels under Orchestrator control — not in-process in the unelevated CLI/UI. Host-only; not used on the installed system’s FirstLogon path. Deep module interface: **ImageServicing** (apply plan to Source ISO → evidence); kernels are thin adapters.
_Avoid_: in-process DISM from the wizard; staging pwsh into the guest for FirstLogon; a fat Servicing monolith or product CLI in `servicing/`

**ImageServicing**:
The elevated imaging deep module: apply BuildPlan artifacts to a user-supplied Source ISO and return image evidence. Production adapter is `pwsh -File` kernels; a C# port type appears only when a test fake shares that shape. Always stamps product-constant offline policies after keep-flag removes ([ADR-009](docs/decisions/ADR-009-product-constant-policies.md)); rejects Store MSIX host pwsh.
_Avoid_: day-one `IServicing` indirection with a single adapter; guest FirstLogon work

**Payload**:
Files staged into the image for Machine setup / FirstLogon: media, `SetupComplete.cmd` (repo: `payload/scripts/` → image: `%WINDIR%\Setup\Scripts\`), the published Provisioning Supervisor binary, and job manifests. Not the Orchestrator. After successful Shell Complete, branded payload under `%WINDIR%\WinMint\` and SetupComplete are best-effort erased ([ADR-008](docs/decisions/ADR-008-residual-minimization.md)); `%ProgramData%\WinMint\` may remain for harness evidence. Product-constant FirstLogon jobs always include OneDrive uninstall + Reserved Storage disable ([ADR-009](docs/decisions/ADR-009-product-constant-policies.md)).
_Avoid_: engine scripts, InstallPlan (v1 staged-profile dump); staged guest PowerShell as the control plane or default install driver; durable brand surface after green FirstLogon; dual `$OEM$` SetupScripts copies

**Machine setup**:
The SetupComplete phase before first interactive logon. Invokes the Provisioning Supervisor in `--machine-setup` mode to stamp autologon and fail-closed verify/restamp Winlogon Shell → Supervisor (after offline Servicing already stamped Shell). Does not run DMA settle, splash, or provisioning jobs.
_Avoid_: winget/toolchain in SetupComplete; calling this FirstLogon; Shell stamp with no verify

**Provisioning Supervisor**:
Single Native AOT C# process used as Winlogon Shell after auth (and as `--machine-setup` during Machine setup). Owns the in-process splash presenter, DMA settle, in-memory status, evidence snapshots, provisioning **phase orchestration**, reboot checkpoint resume, and fail-open to Explorer. Package installs run as delegated child processes (winget/scoop/wsl) or batch import/configure — not necessarily one C# code path per package ([ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md)). There is no peer splash executable and no guest **pwsh product runtime**.
_Avoid_: pwsh PreLock as Shell; a separate Splash.exe; Explorer as first session UI while Shell tenure holds; v1 guest script monolith

**ProvisioningSession**:
The Supervisor’s deep module: Machine setup and Shell-tenure FirstLogon share one phase machine (stamp → splash → DMA settle → jobs → unlock / reboot checkpoint). Modes (`--machine-setup` vs Shell) are entrypoints, not separate architectures.
_Avoid_: splitting splash / settle / jobs into peer processes or a file mailbox control plane; Hyper-V-only executor forks

**Splash**:
The fullscreen Direct2D/GDI presenter surface of the Provisioning Supervisor (same process). Paints its own canvas; does not depend on system theme. Not a separate product host.
_Avoid_: Splash.exe as Shell peer; Avalonia/WebView2/WinUI on the ISO; calling the supervisor “just the splash”

**FirstLogon**:
The live-user setup phase after Windows is installed: Supervisor as Shell, splash, DMA settle, then provisioning jobs when hard settle is green.
_Avoid_: OOBE (unless meaning Microsoft’s own OOBE pages); Machine setup

**Provisioning lock**:
The period while the Provisioning Supervisor is Winlogon Shell and showing splash. Unlock means set Shell to `explorer.exe` and exit. Hard input/task-switch blocking is later hardening, not the core invariant.
_Avoid_: multi-layer PS guard as the definition of lock; releasing Shell then hoping autologon recovers; treating splash as optional decoration during Shell tenure

**Provisioning jobs**:
Install/setup units after DMA hard settle. Supervisor orchestrates phases; packages may run as per-id jobs or **delegated batch** (winget import/configure, batch scoop). Same executor on Smoke and metal; Profile chooses the job set ([ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md)).
_Avoid_: guest pwsh product runtime; Hyper-V-only install executors; starting jobs before hard settle

**Provisioning status**:
In-memory model the Supervisor uses to drive the splash presenter. Optional JSON snapshots are for harness/evidence only — not the control-plane mailbox.
_Avoid_: file-as-source-of-truth for in-process paint; InstallPlan module catalog as the status surface; requiring a second exe to read status

**DMA interop**:
Default-on setup posture that uses a fixed internal region (Ireland / en-IE) during Windows Setup, then restores the user’s visible region at FirstLogon before provisioning jobs.
_Avoid_: EEA country picker, “EU mode” as a user-facing control

**DMA settle**:
Bounded visible-region restore after DMA Setup, judged by a **final snapshot** (not intermediate errors). Locale, GeoID, and time zone are hard gates (mismatch → failed, unlock after failed dwell, no jobs). Location-services posture is soft (warn, continue). Same settle policy on Hyper-V Smoke and bare metal; only acceptance evidence bars may differ.
_Avoid_: Hyper-V-only settle forks; sticky intermediate failures as authoritative; always-continue without a final snapshot; hard-failing FirstLogon solely on location/lfsvc for Smoke

**Smoke**:
The first acceptance vertical: Profile → ISO → unattended Hyper-V install → FirstLogon complete with splash and DMA **hard**-field evidence. Plumbing-focused; not full desktop-product parity. Uses the **test image-quality lane**. Requires Machine setup autologon + Shell stamp correctness when Local+autoLogon is selected. Same Supervisor/settle/job executor as production.
_Avoid_: Primary gate; a different DMA settle or install executor than production

**Primary gate**:
Maintainer acceptance that a **Release**-lane ISO from the frozen `samples/sl7.profile.json` is safe to wipe the primary Surface Laptop 7: Gate B (`metal-acceptance.json` on the same Profile + lane) → destructive install → FirstLogon with online AppX complete, `--package-strict` curated packages green, evidence copy-off + checklist assert. Residual stays ADR-008; leftover-confidence / CDM junk and M4 flags are out of this bar. Until met, Wizard and host-deepening issues are parked.
_Avoid_: stable ISO, hardware campaign (vague), treating Gate B or Smoke alone as wipe confidence

**Image quality**:
Run-specific WIM export / WinSxS cleanup posture for one build. Test lane prioritizes speed; release lane prioritizes a smaller ISO. Not authored in the Profile. Export/commit paths snapshot and assert WIM metadata (Name/Architecture/edition build) so DISM exit 0 cannot silently leave Setup-breaking image info.
_Avoid_: baking Max compression into every Smoke rebuild; claiming C# orchestration makes DISM faster; trusting Unmount/Commit without re-reading Get-WimInfo

**Install engine**:
**WinPE apply** only (`diskpart` + `dism /Apply-Image` + `bcdboot` + Panther OOBE unattend) — no `setup.exe /legacy`. See [workstation-compiler spec](docs/specs/2026-08-05-workstation-compiler-winpe-apply.md).
_Avoid_: treating ISO craftsmanship as the product; resurrecting ConX/Setup `/legacy` as a product dial

**Debloat venue**:
AppX remove-list default is **online** (`debloat.mode` absent ⇒ online): live removes via FirstLogon `appx.safetyNet` after DMA settle. `debloat.mode: offline` keeps DISM `RemoveProvisionedAppx` for air-gap. Capabilities/features are always offline DISM when listed. Network requirement is Plan-derived (`requiresNetwork` on bundle/manifest), not a Profile field — Cli `plan`/`build` and Wizard Preview/Review surface it as a hard warning; Save/Build are not blocked.
_Avoid_: offline-primary debloat as the solo-dev default; authoring `network.*` in Profile JSON; failing Plan solely because FirstLogon will need network

**Keep-flag**:
Remove-list polarity for selected provisioned inbox AppX, capabilities, and optional features: Profile lists what to strip/disable; static in-repo catalogs bound legal ids; AppX via online job (default) or offline DISM (explicit mode); caps/features offline when listed. Product zero-config is host preset **`recommended`** (expands → Profile ids; never preset names in JSON). Smoke **acceptance** uses a small explicit remove-list to prove the path; intentional empty Cli Profiles stay empty. CDM is not the primary control plane.

**Wizard**:
Interactive Avalonia host of the same BuildPlan brain (not a second planner). Authors a **Profile** and **RunOptions** (Source ISO path, image-quality lane, optional WIM index). Source step can unelevated-probe the ISO’s `install.wim` indexes (Wim-Metadata) so the author picks the source archive index Apply exports. During Build, unelevated UI polls `{work}/apply-status.txt` for the current servicing opcode (and log path) — not a fake checklist and not DISM %. Keep-flag UI presets and chip catalogs expand **host-side** into Profile remove-lists / package ids (preset names never appear in Profile JSON). Phase A: multi-step shell (Source → Configure → Preview → Review) with Plan/Save. Phase B: Review **Build** invokes elevated **ImageServicing.Apply** (same path as Cli; UAC via PwshElevatedPlanRunner) — not DISM inside the UI.
_Avoid_: embedding DISM or a second planning brain in the UI; calling the CLI the Wizard; putting keep-flag preset names into Profile JSON; inventing a Wizard-only packages catalog or live winget/Scoop search as the authoring path; WebView2 on the host wizard; forking a second Get-WimInfo dialect outside `servicing/Wim-Metadata.ps1`; inventing a second progress channel beside `apply-status.txt`

**Metal jobs**:
Non-stub provisioning job kinds (`winget`, `scoop`, `wsl`, `package.auditNative`) run by the same Supervisor executor as Smoke stubs, on bare metal or richer profiles.
_Avoid_: Hyper-V-only install executors; guest pwsh adapters as the default driver

**Package catalog**:
Shipped manifest at `config/packages.json` (embedded). **Catalog key** = Wizard chip; **install id** = Profile `packages.*` value. Plan validates fail-closed; debloat stays `CapabilityCatalog`.
_Avoid_: live winget/Scoop search in Wizard; catalog keys in Profile JSON

**Fail-closed (invariant layer)**:
Machine setup stamp, Shell registration, DMA hard fields, debloat/offline policy digests, and Plan validation errors stop the session or build. Host surfaces Plan-derived `requiresNetwork` as a warning only; guest FailOpen when outbound probe fails remains the live gate ([ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md)).
_Avoid_: treating every winget timeout as session Failed during alpha FirstLogon; blocking Save/Build solely because the Profile needs network

**Best-effort (package layer)**:
Curated winget/scoop/wsl installs default to continue-on-failure with `%ProgramData%\WinMint\evidence\packages.evidence.json`; splash summarizes failures; Explorer unlock still follows complete/failed-dwell rules unless an invariant failed first.
_Avoid_: silent swallow without evidence; mixing best-effort with DMA or Shell invariants

**Package phase**:
How Plan stages package work: `perJob` (one spawn per id), `wingetImport` (single `winget import` from staged JSON), `batchScoop` (one `scoop install a b c` after buckets). Alpha default for non-empty winget on arm64: `wingetImport` when import artifact staged; otherwise `perJob` (e.g. non-arm64). Not a CLI/`RunOptions` dial.
_Avoid_: hand-maintaining winget import JSON beside `packages.json`; `winget configure` as default (DSC architecture gap)