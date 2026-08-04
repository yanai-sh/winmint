# Scoop FirstLogon bootstrap — research (2026-08-04)

Question: For WinMint FirstLogon (Supervisor-as-Shell, C# only, **no guest pwsh product control plane**), what is the **official** Scoop install path that works under a local Administrators AutoLogon session with network, and how should offline / missing Scoop fail closed?

WinMint framing: ticket **18** adds Profile `packages.scoop` → BuildPlan `kind: "scoop"` jobs → ProvisioningSession child-process executor. Host Servicing stays pwsh 7.6+; guest product scripts must not be pwsh. Scoop’s own installer is PowerShell — that is Scoop’s installer, not a WinMint guest control plane.

Trust tiers:

- **[primary]** — [ScoopInstaller/Install README](https://github.com/ScoopInstaller/Install/blob/master/README.md), [ScoopInstaller/Scoop README](https://github.com/ScoopInstaller/Scoop/blob/master/README.md), [Scoop wiki Quick Start](https://github.com/ScoopInstaller/Scoop/wiki/Quick-Start)
- **[product]** — WinMint AGENTS / PROVISIONINGSESSION (no guest pwsh product scripts; inbox `powershell.exe` allowed only to run Scoop’s published installer)
- **[inference]** — mapping primary facts onto FirstLogon Admin AutoLogon + `IProcessHost`

## Verdict (short)

| Topic | Lock |
|-------|------|
| Bootstrap URI | Official `https://get.scoop.sh` (Install repo) |
| One-liner (admin) | `iex "& {$(irm get.scoop.sh)} -RunAsAdmin"` **[primary]** |
| Why `-RunAsAdmin` | Installer **blocks** admin consoles by default; WinMint local AutoLogon user is in Administrators |
| Host for installer | Inbox **`powershell.exe`** (Windows PowerShell 5.1+) with `-NoProfile -ExecutionPolicy Bypass` — not `pwsh` as product |
| Network | Required; **fail closed** if `irm` / install exits non-zero (no offline-staged Scoop on ISO unless a later ticket overturns) |
| After install | `%USERPROFILE%\scoop\shims\scoop.cmd` → `scoop install <app>` |
| Offline | No Scoop present + no network ⇒ job fails; do not invent a silent stub success |

Do **not** ship a WinMint-authored Scoop install script. Do **not** use guest `pwsh` for product orchestration. Scoop’s installer may invoke PowerShell internally — that remains Scoop’s responsibility.

## 1. Official install surfaces

Typical (non-admin) **[primary]**:

```powershell
irm get.scoop.sh | iex
```

Admin **[primary]** (Install README “For Admin”):

```powershell
iex "& {$(irm get.scoop.sh)} -RunAsAdmin"
```

Equivalent two-step: `irm get.scoop.sh -outfile install.ps1` then `.\install.ps1 -RunAsAdmin`.

Prerequisites **[primary]**: FullLanguage mode; ExecutionPolicy `RemoteSigned` / `Unrestricted` / `Bypass` for the installer process. Default install dir: `C:\Users\<user>\scoop`.

## 2. WinMint FirstLogon mapping **[inference]**

1. Resolve `scoop.cmd` under `%USERPROFILE%\scoop\shims\`. If present, skip bootstrap.
2. Else spawn inbox `powershell.exe` with Bypass + the official admin one-liner (or download+`-RunAsAdmin`). Non-zero exit ⇒ `jobs.scoop.bootstrap_failed` (fail closed).
3. Spawn `scoop.cmd install <packageId>` (exact id from Profile). Non-zero ⇒ `jobs.failed`.
4. Optional Profile `packages.scoopNeedsReboot` mirrors winget (subset → `needsReboot` on Plan jobs).

Smoke Profiles stay stub-friendly: omit `packages.scoop` unless proving metal.

## 3. Explicitly out

- Offline-staged Scoop payload on the ISO (unless a later research overturn)
- Wizard Scoop UI
- WSL
- Treating Scoop’s PowerShell installer as a WinMint guest pwsh control plane violation (it is third-party bootstrap, not product scripts)

## Sources

- https://github.com/ScoopInstaller/Install/blob/master/README.md (fetched 2026-08-04)
- https://github.com/ScoopInstaller/Scoop/blob/master/README.md
- https://get.scoop.sh
