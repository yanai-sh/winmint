# README best practices — research (2026-07-28)

Question: what makes a good GitHub repository README in 2026 — best practices, and common mistakes / anti-patterns?

Trust tiers used throughout:

- **[official]** — GitHub Docs, GitHub changelog, GitHub Open Source Guides (opensource.guide is GitHub-authored), GFM spec, W3C WAI. These describe documented platform behavior or institutional guidance.
- **[community]** — clearly-labeled community consensus: makeareadme.com (referenced by opensource.guide), awesome-readme, shields.io, 2025–2026 practitioner guides. These are convention, not platform rules. Practitioner-blog numbers (word counts, conversion lifts) are self-reported, unaudited samples — directionally useful, not scientific.

## What makes a good README

A README is the first thing a visitor sees and exists to answer, fast: **what the project does, why it is useful, how to get started, where to get help, and who maintains it** ([official — GitHub Docs, About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)). GitHub Open Source Guides phrase it as four questions: what does it do, why is it useful, how do I get started, where can I get more help — and add that the README is also the place to state goals, contribution stance, and *"if your project is not yet ready for production, write this information down"* ([official — opensource.guide, Starting an Open Source Project](https://opensource.guide/starting-a-project/)).

Two official findings frame everything else:

- Incomplete or confusing documentation is the **single biggest problem** for open source users (GitHub's 2017 Open Source Survey, cited in [official — opensource.guide, Building Welcoming Communities](https://opensource.guide/building-community/)).
- A README should contain **only what developers need to get started**; longer documentation belongs elsewhere (wikis, docs pages) ([official — About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)). This directly counters the occasional community advice that "too long is better than too short" ([community — makeareadme.com](https://www.makeareadme.com/)) — the modern consensus sides with GitHub: keep the README a lobby, link out for depth.

## Best practices

### Sections, and at what project stage

- **At first public visibility:** README plus LICENSE, CONTRIBUTING, and CODE_OF_CONDUCT are the four files every launch should have; the README itself must exist *before* you show the project to anyone ([official — opensource.guide, Starting an Open Source Project](https://opensource.guide/starting-a-project/); [community — makeareadme.com](https://www.makeareadme.com/): "make it the first file you create").
- **Pre-production stage:** state the status explicitly instead of faking completeness. "If you don't want to accept contributions, or your project is not yet ready for production, write this information down… Sometimes people avoid writing a README because they feel like the project is unfinished… these are all very good reasons to write one" ([official — opensource.guide](https://opensource.guide/starting-a-project/)).
- **Once runnable:** installation and usage/quickstart sections with copy-pasteable, tested commands and expected output; link to deeper examples rather than inlining them ([community — makeareadme.com](https://www.makeareadme.com/); [community — openmarkapp.com](https://openmarkapp.com/blog/how-to-write-readme-md)).
- **Once slowed/stopped:** a status note at the top, possibly with a call for maintainers ([community — makeareadme.com](https://www.makeareadme.com/)).
- Sections should be **ordered by decreasing urgency** — what a first-time visitor needs to decide "try it or not" goes first; reference material goes lower or into linked docs ([community — repoclip.io](https://repoclip.io/blog/how-to-write-a-github-readme)).

### "Above the fold"

- The first screen should carry: project name, **one plain-language sentence** stating what it does and for whom, and (once the product exists) a visual of it in action ([community — repoclip.io](https://repoclip.io/blog/how-to-write-a-github-readme); [community — dev.to README fixes 2026](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm)).
- Clarity beats cleverness in the one-liner; visitors skim many repos and reward the one they understand in seconds ([community — repoclip.io](https://repoclip.io/blog/how-to-write-a-github-readme)).

### Length

- Official hard ceiling: GitHub truncates rendered READMEs beyond **500 KiB** ([official — About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
- Community rule of thumb: **~300–1,500 words** scaled to project size; past ~2,000 words, split detail into docs and link ([community — codec8.com](https://codec8.com/blog/how-to-write-good-readme); a self-reported n=100 audit of 10k+-star repos found a similar 800–1,500-word median — [community, unaudited — gingiris.tools](https://gingiris.tools/blog/2026/04/02/github-readme-template-guide/)).
- Short paragraphs (3–4 sentences max), bullets over prose, numbered lists for steps ([community — codec8.com](https://codec8.com/blog/how-to-write-good-readme)).

### Screenshots and GIFs

- Pay off **once there is a real UI/CLI to show**: a screenshot is the minimum, an animated GIF more persuasive; for terminal tools, scripted recorders (e.g. vhs, terminalizer, ScreenToGif) are the standard toolchain ([community — awesome-readme](https://github.com/matiassingers/awesome-readme); [community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide)).
- A real screenshot "proves the product is real"; a placeholder or stock visual does the opposite ([community — dev.to](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm)). So: screenshots **when true**, never before.

### Tables of contents

- GitHub **auto-generates a TOC** ("Outline" menu in the file header) from headings whenever a Markdown file has 2+ headings; all six heading levels are supported ([official — changelog, 2021-04-13](https://github.blog/changelog/2021-04-13-table-of-contents-support-in-markdown-files/); [official — About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
- Community still recommends a **manual linked TOC only for long READMEs** (~5+ sections), because readers may not discover the Outline icon ([community — codec8.com](https://codec8.com/blog/how-to-write-good-readme); [community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide)). Below that length a manual TOC is duplication.
- Every heading gets a stable auto-anchor for deep links; renaming a heading breaks existing anchor links ([official — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).

### GFM-native features worth using

- **Alerts / callouts** (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`): official guidance is to use them **only when crucial, max one or two per document**, never consecutive or nested ([official — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).
- **Theme-aware images** via `<picture>` + `prefers-color-scheme` srcsets: officially supported in Markdown files ([official — changelog, 2022-05-19](https://github.blog/changelog/2022-05-19-specify-theme-context-for-images-in-markdown-beta/); [official — basic writing and formatting syntax, "The Picture element"](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).
- **Mermaid diagrams** (also geoJSON/topoJSON/STL) render natively in Markdown files — diagrams that live as text, diff cleanly, and need no image assets ([official — Creating diagrams](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)).
- **Relative links and image paths** for anything inside the repo: GitHub rewrites them per-branch and they keep working in clones; absolute links are explicitly discouraged ([official — About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
- Task lists, footnotes, tables, autolinks: defined by the [GFM spec](https://github.github.com/gfm/) and the formatting-syntax doc above; useful, but none of them substitute for content.
- `<details>`/`<summary>` collapsible blocks render on GitHub and are a common community trick for hiding long logs/examples ([community — awesome-readme examples](https://github.com/matiassingers/awesome-readme)); not covered by GitHub's own docs, so treat as convention.

### Accessibility

- Alt text is "a short text equivalent of the information in the image" — required on every meaningful image ([official — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).
- Per the W3C WAI decision tree: a **logo/wordmark whose text appears nowhere else on the page** (an "image of text") should have alt text equal to that text; purely decorative images get an empty `alt` ([official — W3C WAI, alt decision tree](https://www.w3.org/WAI/tutorials/images/decision-tree/)).
- Use real heading hierarchy (H1 → H2 → H3, no skipped levels): headings drive GitHub's auto-TOC, anchor links, and screen-reader navigation ([official — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax); [community — codec8.com](https://codec8.com/blog/how-to-write-good-readme)).
- Write in simple language — many readers are not native English speakers ([official — opensource.guide](https://opensource.guide/starting-a-project/)).

## Anti-patterns / common mistakes

- **Placeholder / "coming soon" sections.** "Ship features, then write about them" — placeholder sections read as vapor and rot instantly ([community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide)). The honest alternative is a status line ([official — opensource.guide](https://opensource.guide/starting-a-project/)).
- **Badge walls.** A row of 10–15 badges is visual noise that delays the value proposition; consensus ceiling is ~3–5, each meaningful ([community — dev.to](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm); [community — blog.bobrenze.com](https://blog.bobrenze.com/2026/03/02/agentfolio-badge-embed-best-practices/); [community — openmarkapp.com](https://openmarkapp.com/blog/how-to-write-readme-md)). See next section for the full evidence.
- **Duplicated docs.** README doubles as the full manual → two copies drift. GitHub's own guidance: README is for getting started, longer documentation belongs in wikis/docs ([official — About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
- **Broken links and images.** Signal neglect; using relative in-repo links (officially recommended) is the main preventative, since they survive branches and forks ([official — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax); [community — dev.to](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm)).
- **Marketing-vapor feature lists.** "Revolutionary, blazingly fast, best-in-class" — "show, don't claim" ([community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide)).
- **Emoji overload / tone churn.** No official rule; community consensus is restraint and a consistent voice — emojis are supported via `:code:` but that's a capability, not an endorsement ([official capability — basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax); [community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide)). Note some celebrated READMEs do use emoji section icons — it is a style choice, not a sin ([community — awesome-readme](https://github.com/matiassingers/awesome-readme)).
- **Wall of text.** Unbroken paragraphs go unread; structure for skimming ([community — codec8.com](https://codec8.com/blog/how-to-write-good-readme); [community — openmarkapp.com](https://openmarkapp.com/blog/how-to-write-readme-md)).
- **Stale content.** Outdated install instructions and untested code examples are called "the biggest credibility killer"; test the quickstart fresh before each release ([community — trymarkdownviewer.com](https://trymarkdownviewer.com/blog/github-readme-guide); [community — openmarkapp.com](https://openmarkapp.com/blog/how-to-write-readme-md)). If the project stalls, say so at the top instead of letting the README lie ([community — makeareadme.com](https://www.makeareadme.com/)).
- **Code examples that don't run.** Every command/snippet must be copy-pasteable and verified ([community — openmarkapp.com](https://openmarkapp.com/blog/how-to-write-readme-md)).

## Badges: the evidence

**For badges:**

- Shields.io serves **1.6+ billion badge images/month** and names VS Code, Vue, and Bootstrap as users — badges are an entrenched ecosystem norm ([community — badges/shields README](https://github.com/badges/shields)).
- Top-tier repos do use them — but **few and functional**: facebook/react ships exactly 5 (license, npm version, two CI workflows, "PRs welcome"), every one wrapped in a relevant link ([observed — facebook/react README](https://github.com/facebook/react/blob/main/README.md)); microsoft/vscode ships 3 (open feature-requests, open bugs, chat), all linked ([observed — microsoft/vscode README](https://github.com/microsoft/vscode/blob/main/README.md)).
- Badges communicate live metadata at a glance (build status, version, coverage) and lend credibility **when thoughtfully used** ([community — Talk Python #395](https://talkpython.fm/episodes/show/395/tools-for-readme.md-creation-and-maintenance); [community — makeareadme.com](https://www.makeareadme.com/)).

**Against badges (or for restraint):**

- **Badges are promises.** A badge mirrors live upstream state (version, CI); a badge for a thing that doesn't exist yet is vapor, and a stale/broken badge actively destroys trust ([community — rustfaq.org](https://www.rustfaq.org/en/how-to-use-badges-and-shields-in-cratesio-readme/)).
- **Badge walls are a recognized anti-pattern** — "ten badges isn't impressive, it's overwhelming"; consensus ceiling 3–5, top placement, each wrapped in a link ([community — blog.bobrenze.com](https://blog.bobrenze.com/2026/03/02/agentfolio-badge-embed-best-practices/); [community — dev.to](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm)).
- **Drop badges that duplicate what the text already says** — "badges should summarize, not duplicate" ([community — rustfaq.org](https://www.rustfaq.org/en/how-to-use-badges-and-shields-in-cratesio-readme/)).
- **Vanity badges carry no information** — "Made with ❤️", "Awesome", generic "PRs welcome" are the examples practitioners single out as worthless ([community, unaudited — gingiris.tools](https://gingiris.tools/blog/2026/04/02/github-readme-template-guide/)).
- Some of the most-respected repos run **zero badges**: torvalds/linux's README is a badge-free, image-free text navigation hub organized by reader role — and in 2026 it even includes an "AI Coding Assistant" reader section, a relevant precedent for agent-driven repos ([observed — torvalds/linux README](https://github.com/torvalds/linux/blob/master/README)).

**Synthesis:** the evidence does not support "badges are bloat" as an absolute — it supports **"badges that mirror live, real metadata, kept to a handful and wrapped in links, are useful; everything else is bloat."** Before a project has CI, releases, or a package registry entry, almost every standard badge would be a promise about nothing, so zero badges at pre-release stage is consistent with both the pro- and anti-badge evidence. The one badge whose subject already exists at design phase is the license (React ships one) — but a plain text license link conveys the same fact, which is why the "summarize, don't duplicate" rule cuts against adding it early.

## Applied to WinMint

Current README: 16 lines — centered theme-aware `<picture>` hero with `alt="WinMint"`, a two-sentence tagline (what it is + the user-supplies-the-ISO legal stance), an honest status line, a docs-links row, a license line. Convention under test: *"concise, real, valuable content only; badges are bloat; no placeholder sections; grow on triggers (quickstart at ticket 01, features at smoke pass, badges at first release, screenshots via dark/light `<picture>` block)."*

**Validated by the research:**

- [x] **Honest status line instead of placeholder sections** — exactly what opensource.guide prescribes for not-yet-ready projects, and the anti-pattern lists condemn the "coming soon" alternative ([official](https://opensource.guide/starting-a-project/); [community](https://trymarkdownviewer.com/blog/github-readme-guide)).
- [x] **Theme-aware hero via `<picture>`/srcset** — the officially documented pattern; relative asset paths are the officially recommended form ([official changelog](https://github.blog/changelog/2022-05-19-specify-theme-context-for-images-in-markdown-beta/); [official docs](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)).
- [x] **`alt="WinMint"` on the wordmark** — correct per the W3C decision tree: the logo text appears nowhere else as real text, so alt = the text of the image ([official — W3C WAI](https://www.w3.org/WAI/tutorials/images/decision-tree/)).
- [x] **Above-the-fold content** — name/visual + one-sentence what-it-is + a differentiator (the legal stance) matches the recommended first-screen pattern ([community](https://repoclip.io/blog/how-to-write-a-github-readme)).
- [x] **Docs-links row instead of duplicating docs** — matches GitHub's "README is for getting started, longer docs elsewhere" ([official](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)). Relative links throughout, as recommended.
- [x] **No badges pre-release** — supported by the badge-as-promise argument: CI/version/release badges would be promises about nothing today ([community](https://www.rustfaq.org/en/how-to-use-badges-and-shields-in-cratesio-readme/)). "Badges at first release" is the evidence-consistent trigger; refine it to *≤5 informative badges, each linked, each mirroring live metadata; no vanity badges*.
- [x] **Screenshots deferred until a UI exists** — a placeholder visual is worse than none; screenshots pay off only when real ([community](https://dev.to/iris1031/github-star-growth-7-readme-fixes-for-2026-3mhm)).
- [x] **No manual TOC** — correct at this length; GitHub's Outline covers navigation automatically once headings exist ([official](https://github.blog/changelog/2021-04-13-table-of-contents-support-in-markdown-files/)). Add a manual TOC only if the README grows past ~5 sections.
- [x] **"Lobby, not brochure"** — matches the length consensus (300–1,500 words, link out for depth) far better than makeareadme's contrarian "too long beats too short."

**Where research contradicts or refines the current stance:**

1. **"Badges are bloat" is too absolute.** The evidence condemns badge *walls* and *vanity* badges, not badges themselves; React and VS Code ship a handful of functional ones. The convention's deferral trigger is right, but the rationale in AGENTS.md should read "no badge has live metadata to mirror yet," not "badges are bloat" — otherwise the first-release badge addition will look like a policy reversal. Minor: a license badge is arguably "real" today (the GPL license exists, and React ships one), but the text license link already conveys it — the "summarize, don't duplicate" rule supports keeping it as text.
2. **"Where can I get help" is unanswered.** GitHub's canonical README content list includes where users get help, and the current README has no pointer to the issue tracker (the repo uses GitHub Issues per the agent contract). One link (e.g. "Issues" in the docs row) would close this at zero bloat cost ([official](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)).
3. **Launch checklist debt (not a current defect).** opensource.guide expects CONTRIBUTING and CODE_OF_CONDUCT alongside README+LICENSE at *public launch*. Fine to defer during the design hold, but the growth convention should add a trigger: "CONTRIBUTING + CODE_OF_CONDUCT before public launch / first external contribution" ([official](https://opensource.guide/starting-a-project/)).
4. **Length floor, not just ceiling.** The philosophy guards against bloat but not against unhelpful terseness; community consensus expects install/usage/support sections *once the project is runnable*. The existing triggers (quickstart at ticket 01, features at smoke pass) already schedule exactly this — the research simply confirms those triggers are the right ones and correctly sequenced.
5. **Optional 2026 touches when growth happens:** a Mermaid diagram of the CLI → Servicing → Provisioning pipeline (renders natively, lives as diffable text — [official](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)), and — given the repo is agent-driven — an agent-oriented section has a flagship precedent in torvalds/linux's "AI Coding Assistant" reader section ([observed](https://github.com/torvalds/linux/blob/master/README)); WinMint's AGENTS.md link in the docs row already covers this in spirit.
