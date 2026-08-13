# Contract tests

Prove a script whose runtime host cannot exist on a dev box, or a PowerShell helper whose OS commands are injected.

Belongs here:

- WinPE / DISM / GitHub-release / Prepared-media helpers driven with fixtures (no live ISO, no live WinPE).
- Policy/docs contracts that fail if required sentences disappear.

Does not belong here:

- In-process C# module tests (`tests/WinMint.Tests`).
- Hyper-V Smoke (S4) or Host Apply (S5).
- A contract around the deleted `--reuse-media` / marker four-way branch.

`just check` discovers `tests/contract/Test-*.ps1`. CI runs the same discovery.
