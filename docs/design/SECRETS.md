# Secrets lifecycle (Smoke)

**Status:** Accepted (batch-grill 2026-07-28) — lab / Smoke honesty  
**Authority:** ADR-002 (password-required local), ProvisioningSession Machine setup, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)

## Smoke stance (explicit)

Smoke accounts: **Local + autoLogon only** (password required). Other account modes fail closed at BuildPlan.

Password may appear in:

1. Profile on the **build host** — fixtures may **inline** lab secrets; metal Cli prefers `passwordPath` (resolved by `ProfileFile` relative to the Profile JSON directory; absolute paths stay absolute); Wizard uses a password prompt. **No** `PasswordEnvVar`.
2. Autologon material stamped into the offline image / Machine setup (Windows requirements).

**Lab-grade only** — not enterprise secret management. No BitLocker/TPM-sealed secrets in Smoke.

## Rules

| Rule | Detail |
|------|--------|
| Plan-time | Local+autoLogon without password ⇒ BuildPlan `PlanFailure` |
| Transport | Prefer `passwordPath` (Cli via `ProfileFile`) or Wizard prompt over inline password; fixtures may inline test-only secrets; **no** `PasswordEnvVar` |
| Sources | Non-empty `password` **and** non-empty trimmed `passwordPath` ⇒ document error `account.password.sources.conflict` (before password-file I/O) |
| Materialize | `ProfileFile` reads the password file, strips trailing CR/LF only (never trims contents), keeps authored `passwordPath` on the Profile for safe `SerializeProfile` round-trip |
| Relative path | Ordinary relative `passwordPath` (incl. `..`) resolves against the Profile file directory; Windows drive-relative / root-relative ambient forms fail closed |
| Machine setup | After successful autologon stamp, **wipe** staged bundle password on disk via `WipeSecrets` Action (JSON redact + rewrite; no `FileSecretScrubber` / `ISecretScrubber` class) |
| Evidence | Harness must **redact** passwords from pulled logs/evidence; never commit real passwords |
| Guest jobs JSON | Must not round-trip cleartext password |
| defaultuser0 | Never leave `DefaultUserName=defaultuser0` with `AutoAdminLogon` |

## Out of Smoke

Credential managers, LSA secrets hardening, rotating autologon off after first login — later verticals / ADRs.

## Agent rule

If an implementation “temporarily” logs passwords or ships them in evidence JSON, that is a **spec violation**, not a debug convenience.
