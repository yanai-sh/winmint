# Ephemeral triple score — 2026-08-11

**Rubric:** [2026-08-11-ephemeral-score-rubric.md](../specs/2026-08-11-ephemeral-score-rubric.md)

| Lens | Score | Notes |
|------|-------|--------|
| Prospect | **9**/10 | Live-session + `-PrimaryGate` one-shot; TEMP delete intentional; durable opt-in only |
| Full-flow | **9**/10 | Shared Gate B workdir `%LOCALAPPDATA%\WinMint\work\sl7-primary`; metal ≠ Primary |
| Architect | **9**/10 | Gate B fail-close; mandatory `.sha256`; Primary wipe still unproven (not a demerit for 9) |

**Product implication:** Do **not** chase durable LocalAppData default. Next host leverage is catalog source validity (`just packages-check`), then Primary FU evidence on metal.
