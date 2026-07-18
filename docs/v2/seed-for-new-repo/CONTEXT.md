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
The typed headless brain that validates the Profile, plans the build, and drives elevated servicing and payload staging. Public surface is the C# CLI; the wizard is a later client of the same brain.
_Avoid_: ui-bridge, engine (when meaning the old PowerShell monolith)

**Servicing**:
Offline image work on the WIM/ISO (mount, package/hive changes, export). Executed by elevated PowerShell kernels under Orchestrator control — not in-process in the unelevated CLI/UI.
_Avoid_: in-process DISM from the wizard

**Payload**:
Scripts and assets staged into the image that run during Windows Setup / FirstLogon (machine setup, agent stub, splash host). Not the Orchestrator.
_Avoid_: engine scripts, InstallPlan (v1 staged-profile dump)

**FirstLogon**:
The live-user setup phase after Windows is installed, including provisioning lock, visible-region restore when DMA was used, splash, and agent work.
_Avoid_: OOBE (unless meaning Microsoft’s own OOBE pages)

**DMA interop**:
Default-on setup posture that uses a fixed internal region (Ireland / en-IE) during Windows Setup, then restores the user’s visible region at FirstLogon before further live-user work.
_Avoid_: EEA country picker, “EU mode” as a user-facing control

**Smoke**:
The first acceptance vertical: Profile → ISO → unattended Hyper-V install → FirstLogon complete with splash and DMA restore evidence. Plumbing-focused; not full desktop-product parity. Uses the **test image-quality lane** (fast export; skip component cleanup).
_Avoid_: full install gate, hardware acceptance (those are later verticals)

**Image quality**:
Run-specific WIM export / WinSxS cleanup posture for one build. Test lane prioritizes speed; release lane prioritizes a smaller ISO. Not authored in the Profile.
_Avoid_: baking Max compression into every Smoke rebuild; claiming C# orchestration makes DISM faster
