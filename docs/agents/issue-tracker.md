# Issue tracker: GitHub

Issues are the work surface. Use the `gh` CLI inside the clone (`gh` infers the repo from `git remote`).

## Conventions

- **Create**: `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies)
- **Read**: `gh issue view <number> --comments`
- **List**: `gh issue list --state open --json number,title,body,labels,comments` (add `--label` / `--state` as needed)
- **Comment**: `gh issue comment <number> --body "..."`
- **Labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Labels in active use: `needs-triage` · `needs-info` · `ready-for-agent` · `ready-for-human` · `wontfix` · `wayfinder:*`.

## Pull requests

**PRs as a request surface: no.** Solo maintainer — do not open PRs unless asked. When a skill says “triage PRs,” skip unless this flag is flipped to `yes`.

GitHub shares one number space across issues and PRs: resolve `#n` with `gh pr view n` then fall back to `gh issue view n`.

## Skill phrases

- “publish to the issue tracker” → create a GitHub issue
- “fetch the relevant ticket” → `gh issue view <number> --comments`

## Wayfinding

Used by `/wayfinder`. The **map** is one issue; **children** are tickets.

- **Map**: issue labelled `wayfinder:map` (`gh issue create --label wayfinder:map`). Body holds Notes / Decisions-so-far / Fog.
- **Child ticket**: GitHub sub-issue under the map when available; else task-list link in the map body plus `Part of #<map>` at the top of the child. Labels: `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Claimed tickets get an assignee.
- **Blocking**: native issue dependencies when available (`gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`; database id from `gh api repos/<owner>/<repo>/issues/<n> --jq .id`, not `#number`). Else `Blocked by: #<n>` at the top of the child. Unblocked when every blocker is closed.
- **Frontier**: open children of the map, drop those with an open blocker or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me` (session’s first write).
- **Resolve**: comment the answer, close the issue, append a context pointer to the map’s Decisions-so-far.
