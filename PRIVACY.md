# Privacy

WinMint does not send data off the PC unless you started that step.
WinMint does not transfer information to networked systems unless the operator requested that operation.

When you do, it may contact:

- **GitHub** — download the toolkit zip and checksum, and look up release tags.
- **Microsoft** — you supply the Windows ISO. Servicing can use DISM on that file. Optional Surface drivers and WinGet use Microsoft's servers.
- **WinGet / Scoop** — only if you chose those apps and first sign-in installs them.
- **Package vendor sites** — whatever those apps download.

Work folders and the output ISO stay where you put them. Logs may remain under `%ProgramData%\WinMint\`. A local copy of extracted Windows may remain under `%ProgramData%\WinMint\Servicing\` so a later build can skip re-extracting. That copy is not uploaded.

No telemetry service, no crash-upload endpoint, and no SignPath traffic from your PC until a signed GitHub Release exists and you download it.
