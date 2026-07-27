---
title: Codex Token Tracking
slug: codex-token-tracking
milestone: "0.1.3"
status: proposed
started: 2026-07-27
owner: Suprie
description: >
  Let the user see Codex CLI token usage alongside Claude, ZCode, and Hermes
  in the menu bar app, instead of only tracking those three sources.
---

## Motivation

The app already tracks token usage for Claude, ZCode, and Hermes via
`TokenUsageParser`-conforming parsers wired into `TokenService`. Codex CLI is
a fourth source the user works in that isn't tracked yet, so the dashboard
under-reports total usage and gives no per-session visibility into Codex
sessions. Adding Codex closes that gap using the same parser/service pattern
already established.

## Scope

- Discover Codex CLI's usage/session storage location and format
- `CodexTokenParser` conforming to `TokenUsageParser`
- Wire the new parser into `TokenService` as a new source
- UI: Codex appears as a session source (same treatment as Hermes/ZCode) with
  per-session breakdown
- Totals/aggregates include Codex numbers

## Non-Goals

- Any Codex CLI config or install changes
- Historical backfill of Codex data predating this feature
- Non-token Codex stats (cost estimates, model breakdown) beyond what's
  already done for other parsers

## PRD Index

| PRD | Description | Status |
|-----|-------------|--------|
| [prd-codex-parser](./prd-codex-parser.md) | Discover Codex's storage format and implement `CodexTokenParser` + service wiring + UI | proposed |

## Architecture Decisions

### ADR-1: Codex usage file format — fill in

## Success Criteria

- Codex usage file is parsed and session token counts are shown
- Codex shows up as a separate source in the UI, same as Hermes/ZCode
- Totals/aggregates include Codex numbers correctly

## Risks

| Risk | Mitigation |
|------|------------|
| Codex CLI changes how it stores conversation history/token counts, breaking the parser | Isolate format-parsing logic behind the `TokenUsageParser` protocol (already the pattern for Claude/ZCode/Hermes) so a format change is a localized parser fix, not a service/UI rewrite; add a parser-level test fixture from a real Codex usage file so format drift is caught early |
