# Secrets lifecycle (Smoke)

**Status:** Accepted (batch-grill 2026-07-28) — lab / Smoke honesty  
**Authority:** ADR-002 (password-required local), ProvisioningSession Machine setup, [DESIGN grill locks](../DESIGN.md#decisions-locked-grill)

## Smoke stance (explicit)

Smoke accounts: **Local + autoLogon only** (password required). Other account modes fail closed at BuildPlan.

Password may appear in:

1. Profile on the **build host** — fixtures may **inline** test secrets; Cli should prefer `PasswordPath` / `PasswordEnvVar` when implemented.
2. Autologon material stamped into the offline image / Machine setup (Windows requirements).

**Lab-grade only** — not enterprise secret management. No BitLocker/TPM-sealed secrets in Smoke.

## Rules

| Rule | Detail |
|------|--------|
| Plan-time | Local+autoLogon without password ⇒ BuildPlan `PlanFailure` |
| Transport | Prefer `PasswordPath` / `PasswordEnvVar` in Profile over inline password when Cli supports it; fixtures may inline test-only secrets |
| Machine setup | After successful autologon stamp, **wipe** staged bundle password on disk via `WipeSecrets` Action (JSON redact + rewrite; no `FileSecretScrubber` / `ISecretScrubber` class) |
| Evidence | Harness must **redact** passwords from pulled logs/evidence; never commit real passwords |
| Guest jobs JSON | Must not round-trip cleartext password |
| defaultuser0 | Never leave `DefaultUserName=defaultuser0` with `AutoAdminLogon` |

## Out of Smoke

Credential managers, LSA secrets hardening, rotating autologon off after first login — later verticals / ADRs.

## Agent rule

If an implementation “temporarily” logs passwords or ships them in evidence JSON, that is a **spec violation**, not a debug convenience.
