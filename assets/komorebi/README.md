# WinWS Komorebi preset

This payload is copied during FirstLogon when the Komorebi desktop layer is selected.

Komorebi and whkd are installed from Winget using the current host architecture. `applications.json` is a small fallback; FirstLogon asks Komorebi to fetch the latest application-specific configuration when network access is available.
