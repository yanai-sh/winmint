# Copy seed → new GitHub repository

This file lives in the **v1** repo only (`docs/v2/`). It is **not** part of the winmint-v2 initial commit. The seed zip is self-contained — see seed [`docs/START.md`](seed-for-new-repo/docs/START.md) if you only have the archives.

## Archives

| Zip | Role |
|-----|------|
| `dist/winmint-v2-seed-*.zip` | **Commit 1** — extract contents as the new repo root |
| `dist/winmint-v2-future-assets-*.zip` | Deferred shelf — keep outside the new repo until wizard/shell verticals |

WinMint **v1** stays a separate folder/repo for behaviour reference ([seed `PORT-FROM-V1.md`](seed-for-new-repo/docs/PORT-FROM-V1.md)).

## Steps

1. Create the empty GitHub repo (no README/license from the GitHub UI if you will push the seed as commit one).
2. Copy the **contents** of [`seed-for-new-repo/`](seed-for-new-repo/) (or extract the seed zip) to the new repo root — not the `seed-for-new-repo` folder name itself.
3. Do **not** copy [`future-assets/`](future-assets/) into commit 1. Park the future-assets zip beside the new repo if you want it handy.
4. In the new repo:

```powershell
git init
git add .
git commit -m "chore: initial winmint-v2 starter"
git branch -M main
git remote add origin git@github.com:<owner>/<repo>.git
git push -u origin main
```

5. Follow [`seed-for-new-repo/docs/START.md`](seed-for-new-repo/docs/START.md): issue-tracker slug, `just check`, `/setup-matt-pocock-skills` → Smoke spec.

## What the seed includes

Solution scaffold (`WinMint.slnx`, `src/`, `tests/`), docs/ADRs, `assets/brand/`, `payload/media/`, servicing stubs, Justfile, CI, LICENSE — see [`seed-for-new-repo/docs/START.md`](seed-for-new-repo/docs/START.md) and [`STRUCTURE.md`](seed-for-new-repo/docs/STRUCTURE.md).

Deferred WSL/editor/desktop icons and shell presets: [`future-assets/`](future-assets/).
