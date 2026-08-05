# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

Closed index: [TICKETS](../TICKETS.md). Apply `ready-for-agent` only when starting an implement session on that issue. Optional local drafts: `.scratch/winmint-v2-smoke/issues/`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Wayfinder maps and decision tickets live as GitHub issues. Requires `gh` ≥ 2.94 (parent / blocked-by flags).

### Labels

| Label | Role |
|-------|------|
| `wayfinder:map` | The map issue (index only) |
| `wayfinder:research` | AFK research decision ticket |
| `wayfinder:grilling` | HITL grilling decision ticket |
| `wayfinder:prototype` | HITL prototype decision ticket |
| `wayfinder:task` | Task that unblocks a decision |

### Map and children

- **Create a map**: `gh issue create --title "..." --label "wayfinder:map" --body "..."` with Destination, Notes, Decisions so far, Not yet specified, Out of scope.
- **Create a child ticket**: `gh issue create --title "..." --label "wayfinder:<type>" --parent <map-number> --body "## Question"$'\n\n'..."`. Body is the question only.
- **Wire blocking** (second pass, after ids exist): `gh issue edit <number> --add-blocked-by <blocker-number>`.
- **Claim**: assign the ticket to the driver before work (`gh issue edit <number> --add-assignee "@me"`). An open unassigned child is unclaimed.
- **Frontier**: open children of the map that have no open blockers and no assignee.
- **Resolve**: post a resolution comment, close the issue, append one gist line to the map’s **Decisions so far** (link the ticket by **title**, with the URL inside the name — never bare `#N` alone in narration).

### Refer by name

In narration and in the map’s Decisions-so-far, refer to tickets by **title** wrapping the issue link — e.g. [Keep/exclude polarity and presets](https://github.com/yanai-sh/winmint/issues/N) — not by bare id.
