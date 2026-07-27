---
prd: prd-codex-parser
epic: codex-token-tracking
milestone: "0.1.3"
status: proposed
description: >
  Discover Codex CLI's session/token storage format and add a
  CodexTokenParser so Codex usage shows up in TokenService and the menu bar
  UI alongside Claude, ZCode, and Hermes.
---

## Overview

The app tracks token usage for Claude, ZCode, and Hermes through parsers that
conform to `TokenUsageParser` (`ClaudeMonitor/Services/TokenUsageParser.swift`)
and are fanned out concurrently by `TokenService`
(`ClaudeMonitor/Services/TokenService.swift:19-24`). This PRD adds Codex CLI
as a fourth source using the same pattern.

## Problem Statement

Codex CLI usage isn't tracked at all today, so the user's totals and
per-session breakdown under-represent their actual usage across tools.

## Goals

| Priority | Goal |
|----------|------|
| P0 | Discover where/how Codex CLI stores session + token usage data |
| P0 | `CodexTokenParser` conforming to `TokenUsageParser`, returning `[TokenUsage]` with `source: .codex` |
| P0 | `TokenService` includes `CodexTokenParser()` in its default parsers array |
| P0 | Menu bar UI shows Codex sessions/totals same as Hermes/ZCode |
| P1 | Parser has a test fixture derived from a real Codex usage file |

## Non-Goals

- Codex CLI config/install changes
- Historical backfill of Codex data predating this feature
- Non-token Codex stats (cost estimates, model breakdown) beyond parity with
  existing parsers

## Design

_Fill in once Phase 1 discovery lands — the storage format determines
whether this parser reads JSONL (like `TokenParser`) or SQLite (like
`ZCodeTokenParser`/`HermesTokenParser`)._

## Phases

### Phase 1 — Discovery
- [ ] `codex-parser/discover-storage-format` Find Codex CLI's session/token storage location and format

### Phase 2 — Parser
- [ ] `codex-parser/add-token-source-case` Add `.codex` case to `TokenSource` enum (tag, label)
- [ ] `codex-parser/implement-parser` Implement `CodexTokenParser` conforming to `TokenUsageParser`

### Phase 3 — Wiring
- [ ] `codex-parser/register-in-service` Register `CodexTokenParser()` in `TokenService`'s parsers array

### Phase 4 — UI & Verification
- [ ] `codex-parser/verify-ui-rendering` Verify/update `MenuBarView` renders Codex source (badge, per-session breakdown, totals)
- [ ] `codex-parser/parser-test-fixture` Add a parser test using a real Codex usage file fixture

## Open Questions

- Does Codex CLI store usage as JSONL, SQLite, or something else, and where
  (path)?
- Does Codex expose reasoning tokens the way ZCode does (folded into
  output), or a different breakdown?
- Does Codex track per-session titles/working directories out-of-band, or
  are they embedded in the usage rows?
