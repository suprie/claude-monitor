---
prd: prd-codex-parser
epic: codex-token-tracking
milestone: "0.1.3"
status: completed
description: >
  Discover Codex CLI's session/token storage format and add a
  CodexTokenParser so Codex usage shows up in TokenService and the menu bar
  UI alongside Claude, ZCode, and Hermes.
---

## Overview

The app tracks token usage for Claude, ZCode, and Hermes through parsers that
conform to `TokenUsageParser` (`TakarPakai/Services/TokenUsageParser.swift`)
and are fanned out concurrently by `TokenService`
(`TakarPakai/Services/TokenService.swift:19-24`). This PRD adds Codex CLI
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

Codex CLI writes one JSONL rollout file per session at
`~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<timestamp>-<uuid>.jsonl` — so
`CodexTokenParser` reads JSONL line-by-line like `TokenParser`, not SQLite
like `ZCodeTokenParser`/`HermesTokenParser`.

Per rollout file:
- `session_meta` line → `sessionId` = `payload.id`, `projectPath` = `payload.cwd`
- `turn_context` lines → `model` = latest `payload.model` seen before each
  `token_count` event (e.g. `"gpt-5-codex"`)
- `event_msg` lines with `payload.type == "token_count"` → one `TokenUsage`
  record per event, using `info.last_token_usage` (per-turn delta, not
  `info.total_token_usage` which is session-cumulative):
  - `timestamp` = event's top-level `timestamp`
  - `inputTokens` = `last_token_usage.input_tokens`
  - `cacheReadTokens` = `last_token_usage.cached_input_tokens`
  - `cacheCreationTokens` = `0` (Codex has no creation/read split)
  - `outputTokens` = `last_token_usage.output_tokens` +
    `last_token_usage.reasoning_output_tokens` (Codex reports reasoning
    separately; `TokenUsage` has no reasoning field, so fold it into output,
    matching how `ZCodeTokenParser` handles reasoning tokens)
  - `source` = `.codex`

Full rationale in `decisions.md` (2026-07-27 entries).

## Phases

### Phase 1 — Discovery
- [x] `codex-parser/discover-storage-format` Find Codex CLI's session/token storage location and format

### Phase 2 — Parser
- [x] `codex-parser/add-token-source-case` Add `.codex` case to `TokenSource` enum (tag, label)
- [x] `codex-parser/implement-parser` Implement `CodexTokenParser` conforming to `TokenUsageParser`

### Phase 3 — Wiring
- [x] `codex-parser/register-in-service` Register `CodexTokenParser()` in `TokenService`'s parsers array

### Phase 4 — UI & Verification
- [x] `codex-parser/verify-ui-rendering` Verify/update `MenuBarView` renders Codex source (badge, per-session breakdown, totals)
- [x] `codex-parser/parser-test-fixture` Add a parser test using a real Codex usage file fixture

## Open Questions

- Does Codex CLI store usage as JSONL, SQLite, or something else, and where
  (path)?
- Does Codex expose reasoning tokens the way ZCode does (folded into
  output), or a different breakdown?
- Does Codex track per-session titles/working directories out-of-band, or
  are they embedded in the usage rows?
