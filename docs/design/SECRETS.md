# Secrets lifecycle (Smoke)

**Authority:** [DESIGN](../DESIGN.md) · ProvisioningSession Machine setup

Smoke accounts: **Local + autoLogon** (password required). Lab-grade — not enterprise secret management.

## Rules

| Rule | Detail |
|------|--------|
| Plan-time | Local+autoLogon without password ⇒ `Failure` |
| Transport | Prefer `passwordPath` (`ProfileFile`) or Wizard prompt; fixtures may inline test secrets |
| Sources | Both non-empty `password` and `passwordPath` ⇒ `account.password.sources.conflict` |
| Materialize | `ProfileFile` reads file, strips trailing CR/LF only; keeps authored path for serialize |
| Relative path | Resolve against Profile directory; ambient drive/root-relative forms fail closed |
| Machine setup | After stamp, wipe staged bundle password on disk (`WipeSecrets`) |
| Evidence | Redact passwords from pulled logs; never commit real passwords |
| Guest jobs JSON | Must not round-trip cleartext password |
| defaultuser0 | Never leave with AutoAdminLogon |

Logging or shipping passwords in evidence is a **spec violation**, not a debug convenience.

## Primary / Gate B (sl7)

Create the lab password file (no trailing newline required beyond `-NoNewline`):

```powershell
Set-Content -Path .scratch/sl7.password -Value 'your-lab-password' -NoNewline
```

Profile field: `passwordPath` → `../.scratch/sl7.password` from `samples/`.  
`samples/sl7.profile.json` sets `requireWifiDuringOobe: true` → OOBE **Network** page is expected; do not treat that as “walk away from Wi‑Fi.”
