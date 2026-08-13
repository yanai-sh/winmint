# Incident: Authenticode / GitHub Release compromise

Use this when a GitHub Release, SignPath certificate, API token, or workflow may be compromised, or SignPath notifies the project. There is no signing pipeline today; these steps apply only after one exists.

1. Disable the `release` workflow and the `release-signing` environment secret (`SIGNPATH_API_TOKEN`) so nothing new publishes.
2. Notify SignPath and request project/policy suspension and certificate/request revocation as they advise.
3. Remove affected GitHub Release assets or mark those GitHub Releases withdrawn. Do not leave a known-bad ZIP downloadable.
4. Publish a GitHub Security Advisory when operators need to act.
5. Record affected tags, commits, SignPath request IDs, hashes, and timestamps on the advisory and on issue #112.
6. Update bootstrap denylist metadata for known affected release hashes/request IDs (when that denylist exists).
7. Rotate the SignPath API token and review GitHub and SignPath audit logs.
8. Fix the pipeline or source. Obtain explicit SignPath and owner approval before resuming tags.

Revocation cannot erase already downloaded bytes. New installs fail closed if revocation status is unavailable. Canonical bootstrap is: download `winmint.ps1` to a file, verify, `pwsh -File`. `irm | iex` is weaker. `-Force` does not skip verification.
