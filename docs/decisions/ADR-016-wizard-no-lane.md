# ADR-016: Wizard never exposes Lane

**Status:** Accepted · **Date:** 2026-10-06

### Context

`Test` | `Release` (**Lane**) is an image-quality run override for pre-release harnesses (Smoke, Host Apply, maintainer Cli). The alpha Wizard still shows Test/Release chips. Final users must not choose compression/cleanup trade-offs or learn the word Lane; their chooser is **Station outcome** (Comfort / Minimal / Power).

### Rejected

- Keeping Test vs Release as a Wizard radio for end users.
- Retiring Lane from Cli/Smoke immediately (harness still needs a fast Test path).
- Teaching Lane as part of the Station UX story.

### Decision

The shipping Wizard Apply path uses shipping image-quality / Gate B semantics only — no Lane control in the UI. Cli, Smoke, and other maintainer tools may keep `Test` | `Release`. Do not restore Wizard Lane chips as a “feature.”

### Review trigger

A deliberate product shift to expose image-quality trade-offs to end users, or harnesses that no longer need a distinct Test export path.
