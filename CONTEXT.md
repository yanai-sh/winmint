# WinMint

Windows 11 ISO customization product. The user supplies official Microsoft media; WinMint produces a tailored install image and first-logon setup.

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
The elevated imaging deep module: apply BuildPlan artifacts to a user-supplied Source ISO and return image evidence. Production adapter is `pwsh -File` kernels; a C# port type appears only when a test fake shares that shape.
_Avoid_: day-one `IServicing` indirection with a single adapter; guest FirstLogon work

**Payload**:
Files staged into the image for Machine setup / FirstLogon: media, `SetupComplete.cmd` (repo: `payload/scripts/` → image: `%WINDIR%\Setup\Scripts\`), the published Provisioning Supervisor binary, and job manifests. Not the Orchestrator.
_Avoid_: engine scripts, InstallPlan (v1 staged-profile dump); staged guest PowerShell as the control plane or default install driver

**Machine setup**:
The SetupComplete phase before first interactive logon. Invokes the Provisioning Supervisor in `--machine-setup` mode to stamp autologon and fail-closed verify/restamp Winlogon Shell → Supervisor (after offline Servicing already stamped Shell). Does not run DMA settle, splash, or provisioning jobs.
_Avoid_: winget/toolchain in SetupComplete; calling this FirstLogon; Shell stamp with no verify

**Provisioning Supervisor**:
Single Native AOT C# process used as Winlogon Shell after auth (and as `--machine-setup` during Machine setup). Owns the in-process splash presenter, DMA settle, in-memory status, evidence snapshots, provisioning jobs, reboot checkpoint resume, and fail-open to Explorer. There is no peer splash executable and no guest PowerShell runtime requirement. Deep module interface: **ProvisioningSession** (one phase machine; modes are entrypoints).
_Avoid_: pwsh PreLock as Shell; a separate Splash.exe; Explorer as first session UI while Shell tenure holds; guest pwsh adapters

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
Install/setup units the Supervisor runs as child processes (`winget`, Scoop, `wsl`, etc.) after DMA settle’s hard fields are green. Smoke and bare metal use the same executor; they may differ in which jobs the Profile schedules, not in how jobs run.
_Avoid_: guest pwsh adapter modules as the default driver; Hyper-V-only install executors; starting jobs before hard settle

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
_Avoid_: full install gate, hardware acceptance (those are later verticals); a different DMA settle or install executor than production

**Image quality**:
Run-specific WIM export / WinSxS cleanup posture for one build. Test lane prioritizes speed; release lane prioritizes a smaller ISO. Not authored in the Profile.
_Avoid_: baking Max compression into every Smoke rebuild; claiming C# orchestration makes DISM faster

**Keep-flag**:
Remove-list polarity for selected provisioned inbox AppX: Profile lists what to strip; a static in-repo catalog bounds legal ids; ImageServicing removes offline; ProvisioningSession is a narrow FirstLogon safety net. Smoke acceptance uses a small explicit remove-list to prove the path; other Profiles default empty.
_Avoid_: keep-list polarity; Profile presets; BCU; treating capabilities/CDM as the primary remove path; auto-on “recommended” sets outside an explicit Profile list

**Wizard**:
Interactive host of the same BuildPlan brain (not a second planner). Keep-flag UI presets expand **host-side** into a Profile remove-list (preset names never appear in Profile JSON). May also author Profile `packages.winget` / `packages.scoop` and their `*NeedsReboot` subset lists as raw package ids (ids live in the Profile — not host-only preset names).
_Avoid_: embedding DISM or a second planning brain in the UI; calling the CLI the Wizard; putting keep-flag preset names into Profile JSON; inventing a Wizard-only packages catalog or live winget/Scoop search as the authoring path

**Metal jobs**:
Non-stub provisioning job kinds (first: `winget`) run by the same Supervisor executor as Smoke stubs, on bare metal or richer profiles.
_Avoid_: Hyper-V-only install executors; guest pwsh adapters as the default driver
