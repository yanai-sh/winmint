# Samples

| Sample | Purpose | Lane | Wipe risk |
|--------|---------|------|-----------|
| `smoke.profile.json` | Hyper-V plumbing | Test | No |
| `acceptance.profile.json` | Smoke acceptance pins | Test | No |
| `israel.profile.json` | DMA settle lab | Test | No |
| `sl7.profile.json` | Gate B / Primary wipe template | Release via `primary-gate` | Yes — needs passwordPath |

Host preset **`recommended`** expands to remove-lists at plan time; JSON never embeds preset names.

`sl7.profile.json` password: `.scratch/sl7.password` ([SECRETS](../docs/design/SECRETS.md)).
