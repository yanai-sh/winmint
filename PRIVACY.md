# Privacy

WinMint does not transfer information to networked systems unless the operator requested that operation.

When the operator asks, WinMint may contact:

- **GitHub** — download a GitHub Release toolkit ZIP and checksum; API lookups for tags.
- **Microsoft** — Source ISO is operator-supplied (not downloaded by WinMint). Offline servicing may use DISM against that media. Optional Surface Catalog driver fetch uses Microsoft download URLs from the in-repo catalog. WinGet source update/install uses Microsoft WinGet endpoints.
- **WinGet / Scoop** — package resolve and install only when the Profile lists those packages and FirstLogon/jobs run them.
- **Package vendor endpoints** — whatever the selected WinGet/Scoop packages fetch.

The portable toolkit stores Apply workdirs and Output ISOs on disk where the operator pointed them. Guest evidence may remain under `%ProgramData%\WinMint\` after Supervisor self-erase. Host **Prepared media** under `%ProgramData%\WinMint\Servicing\` is a local Source ISO tree, not a network cache.

No telemetry service, no crash-upload endpoint, and no SignPath traffic from operator machines until a signed GitHub Release exists and the operator downloads it.
