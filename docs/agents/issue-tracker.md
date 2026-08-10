# Issue tracker: GitHub

Issues live as GitHub issues. Use the `gh` CLI.

## Conventions

- **Create:** `gh issue create --title "..." --body "..."` (heredoc for multi-line).
- **Read:** `gh issue view <number> --comments`
- **List:** `gh issue list --state open --json number,title,body,labels,comments`
- **Comment:** `gh issue comment <number> --body "..."`
- **Labels:** `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close:** `gh issue close <number> --comment "..."`

Repo from `git remote` when inside a clone.

## Pull requests

**No.** Solo maintainer — do not open PRs unless explicitly asked. Issues are the work surface; merge locally after push when needed.

## Labels

Apply `ready-for-agent` only when starting an implement session on that issue. Triage map: [triage-labels](triage-labels.md).

When a skill says “publish to the issue tracker” → create a GitHub issue.  
When a skill says “fetch the relevant ticket” → `gh issue view <number> --comments`.

## Wayfinding

Wayfinder maps/children use `wayfinder:*` labels (`gh` ≥ 2.94 for parent / blocked-by).

| Label | Role |
|-------|------|
| `wayfinder:map` | Map issue (index only) |
| `wayfinder:research` | AFK research decision |
| `wayfinder:grilling` | HITL grilling decision |
| `wayfinder:prototype` | HITL prototype decision |
| `wayfinder:task` | Task that unblocks a decision |

Create map with Destination / Notes / Decisions so far / Not yet specified / Out of scope. Children: question-only body + `--parent`. Wire `--add-blocked-by` after ids exist. Claim with assignee. Resolve: comment + close + append gist to map **Decisions so far** by **title** + URL (not bare `#N`).
