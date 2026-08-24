# ADR-009: Product posture is not a Profile preset

**Status:** Accepted · Implementation: `ProductPosture` in code.

### Context

ADR-005 forbids AppX preset names in Profile JSON. That is not “no product-constant settings.” Quiet Edge/OneDrive/consumer policy is always-on; the user did not toggle it.

### Rejected

Reading ADR-005 as no product posture. Putting AppX preset names in JSON. Making CDM primary. Treating the id list in this file as law (it would drift).

### Decision

Always-on posture exists: offline policy stamps + fixed FirstLogon jobs, with no Profile toggle.

**Concrete ids, opcodes, and digest keys live in `ProductPosture` and tests** — not here.

Optional Profile `policies` (e.g. DoH) may exist; omit = defaults. Derived stamps (e.g. Brave debloat iff Brave is selected) are code.

This does not make CDM primary ([ADR-007](ADR-007-cdm-not-primary.md)).

### Review trigger

A setting in posture should be a Profile toggle, or a required removal should not be silent.
