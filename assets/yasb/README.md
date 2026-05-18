# WinMint YASB preset

This payload is copied to `%USERPROFILE%\.config\yasb` during FirstLogon when the YASB desktop layer is selected.

The preset intentionally excludes API keys, machine-local state, logs, and backup files from the development machine. Keep weather or other network-backed widgets disabled unless the config can use user-provided secrets.
