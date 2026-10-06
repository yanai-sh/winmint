---
name: microsoft-docs
description: Query official Microsoft documentation for Windows servicing, DISM, WinPE, PowerShell, .NET, and related Learn content. Prefer Microsoft Learn MCP; use Context7 only for docs that live outside learn.microsoft.com.
---

# Microsoft docs (WinMint)

Research skill for Microsoft tech this repo actually touches: offline image servicing, WinPE, unattend/OOBE, PowerShell 7, .NET 11, Avalonia-adjacent Win32, GitHub Actions.

## Default: Microsoft Learn MCP

Use for everything on learn.microsoft.com:

| Tool | Purpose |
|------|---------|
| `microsoft_docs_search` | Concepts, guides, configuration |
| `microsoft_code_sample_search` | Snippets — pass `language` (`csharp`, `powershell`, …) |
| `microsoft_docs_fetch` | Full page when search excerpts are thin |

Typical WinMint queries: DISM mount/export, `install.wim` / `boot.wim`, WinPE, unattend passes, AppX deprovision, Catalog / MSU apply, `pwsh` 7 hosting.

### CLI fallback

If Learn MCP is unavailable:

```bash
npx @microsoft/learn-cli search "DISM Mount-WindowsImage"
```

| MCP | CLI |
|-----|-----|
| `microsoft_docs_search` | `mslearn search "..."` |
| `microsoft_code_sample_search` | `mslearn code-search "..." --language csharp` |
| `microsoft_docs_fetch` | `mslearn fetch "<url>"` |

## Outside Learn — Context7

Resolve a library id once per session, then query:

| Topic | Start with |
|-------|------------|
| Avalonia | Context7 resolve `Avalonia` |
| GitHub Actions / `gh` | `/websites/github_en`, `/websites/cli_github` |
| VS Code (rare here) | `/websites/code_visualstudio` |

Do **not** reach for Aspire, Agent Framework, Semantic Kernel, or Azure app-host docs unless the task explicitly involves those products.

## Query shape

Be specific: product + intent + language.

```
# good
"DISM Add-WindowsPackage MSU offline image"
"WinPE winpeshl.ini launch app"
".NET 11 LibraryImport P/Invoke source generation"

# bad
"Windows"
"Azure"
```
