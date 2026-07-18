# Issue tracker: GitHub

Issues and specs live as GitHub issues. Use the `gh` CLI.

Infer the repo from `git remote -v` inside a clone.

- **Repo slug:** set after create — e.g. `yanai-sh/winmint-v2`  
  (replace this line once the remote exists; `/setup-matt-pocock-skills` may overwrite this file.)

## Conventions

- **Create:** `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies)
- **Read:** `gh issue view <number> --comments`
- **List:** `gh issue list --state open --json number,title,body,labels,comments`
- **Comment:** `gh issue comment <number> --body "..."`
- **Labels:** `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close:** `gh issue close <number> --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.**

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding

Prefer `/to-spec` for Smoke. Use `/wayfinder` only if the Smoke spec is blocked by fog — see [WORKFLOW.md](../WORKFLOW.md).
