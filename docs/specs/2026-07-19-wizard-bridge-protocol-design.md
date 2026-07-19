# Spec: Wizard bridge protocol polish (Track C)

**Date:** 2026-07-19  
**Status:** Ready for tickets  
**Parent grill:** [2026-07-19-polish-program-grill-outcomes.md](2026-07-19-polish-program-grill-outcomes.md)

## Problem Statement

The WebView2 wizard invokes PowerShell ui-bridge scripts and parses success by taking the last `{…}` line of stdout. Multi-line JSON or interleaved logs break ISO probe / dry-run / profile authoring in the GUI even when the bridge succeeded.

## Solution

Define a small, explicit stdout protocol (NDJSON event lines or a single length-prefixed/final JSON document) between `tools/ui-bridge/` and the wizard host, with contract tests on both sides. No new user-facing wizard features.

## User Stories

1. As a wizard user, I want ISO probe results to parse reliably, so that I can pick a Source ISO without false failures.
2. As a wizard user, I want dry-run / validate bridge calls to return structured errors, so that I can fix Profile issues.
3. As a maintainer, I want the bridge protocol documented and contract-tested, so that log noise cannot break the host parser.
4. As a host developer, I want a single parse entrypoint, so that WizardBridge does not rely on last-brace heuristics.

## Implementation Decisions

- Prefer NDJSON: one JSON object per line; final line is `{"type":"result",…}` (or equivalent), host ignores non-JSON lines.
- Alternative acceptable if smaller: bridge writes only one JSON document to stdout and all logs to stderr (already partially true—enforce and test).
- Keep `tools/ui-bridge/` as the PowerShell boundary (ADR-003); do not move DISM into the host.
- Version the protocol with a `schemaVersion` field on result objects.

## Testing Decisions

- Contract tests: sample bridge stdout fixtures → host parser (or a shared pure parse helper) accepts multi-line noise + result.
- Prefer testing the parse seam without launching WebView2 when possible.

## Seams

1. Bridge stdout protocol (highest seam).
2. WizardBridge parse helper consumed by the WebView2 host.

## Out of Scope

- Avalonia / v2 wizard; changing Profile schema; new bridge operations beyond making existing ones reliable.

## Further Notes

Later priority vs Track A/B must items. Can ship independently once tickets exist.
