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

`needs-triage` · `needs-info` · `ready-for-agent` · `ready-for-human` · `wontfix`

Apply `ready-for-agent` only when starting an implement session on that issue.

When a skill says “publish to the issue tracker” → create a GitHub issue.  
When a skill says “fetch the relevant ticket” → `gh issue view <number> --comments`.
