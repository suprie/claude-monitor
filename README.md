# Takar Pakai

Takar Pakai is a native macOS menu bar and dashboard app for inspecting local
token usage from supported coding and AI-agent harnesses. It reads the local
history written by each harness, normalizes it into one model, persists a local
SwiftData cache, and presents totals, charts, conversations, and token
breakdowns.

The app is local-first: source files and databases remain authoritative, the
cache is app-owned derived data, and no source data is modified.

## What it supports

The app currently supports these recording harnesses:

| Harness | Source | Local data read | Granularity | Titles |
| --- | --- | --- | --- | --- |
| Claude Code | `Claude` | `~/.claude/projects/**/*.jsonl` | Request/assistant events | `ai-title`, then first useful user prompt |
| ZCode CLI | `ZCode` | `~/.zcode/cli/db/db.sqlite` | Completed model requests | SQLite `session.title` |
| Hermes CLI | `Hermes` | `~/.hermes/state.db` | Lifetime session/model/provider aggregates | Stored in the sessions table, for query metadata |
| Codex CLI | `Codex` | `~/.codex/sessions/YYYY/MM/DD/**/*.jsonl` | Per-turn token events | Not currently supplied by the rollout format |
| DeepSeek Harness | `DeepSeek Harness` | `~/.dsh/storages/session_projcache/sessions/*.json` | Lifetime session aggregates | Persisted session title |

Missing or uninstalled harness data is reported as a source-level `missing`
status and does not prevent the other sources from loading. Malformed records
are skipped by the relevant parser. SQLite sources are opened read-only.

DeepSeek Harness currently reads the fast per-session JSON aggregates. It does
not read the compressed `session.v4.jsonl.zstd` stream, so its usage is not
available as request-level or day-level history. Hermes has the same
aggregate-only limitation because its source stores session/model totals with
`last_seen`, not individual request events.

## Features

- Menu bar token total for today, with daily, weekly, and monthly summaries.
- Automatic refresh every 60 seconds plus manual refresh.
- Main dashboard with Today, This Week, This Month, and All Time periods.
- Daily usage charts, provider totals, model breakdowns, and session lists.
- Conversation search, source/provider/model filters, and sorting by recent
  activity or token usage.
- Conversation detail with lifetime and selected-period totals, model/provider
  breakdowns, token categories, request timelines where available, and clear
  aggregate-only messaging where a timeline cannot be reconstructed.
- Source-qualified stable conversation identity, so identical session IDs from
  different harnesses remain separate.
- Launch at Login support and a normal macOS app window alongside the menu bar
  extra.
- Persistent local cache with last-known data retained when a source is
  temporarily unavailable.

## Architecture

The runtime is organized as a source-adapter pipeline:

```text
Claude JSONL ───────┐
ZCode SQLite ───────┤
Hermes SQLite ──────┤──> TokenUsageParser actors
Codex JSONL ────────┤            │
DeepSeek JSON ──────┘            ▼
                       SourceImportResult values
                                  │
                                  ▼
                         TokenService refresh loop
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
             UsageRepository                UsageQuery
             SwiftData cache             period/aggregate queries
                    │                           │
                    └─────────────┬─────────────┘
                                  ▼
             Menu bar · Home · Conversations · Detail · Settings
```

### Models

`TokenUsage` is the normalized record shared by every source. Each record
preserves timestamp, model, token categories, session, project path, source,
billing provider, provider metadata provenance, and data granularity.

`TokenSource` identifies the recording harness; `BillingProvider` is kept
separate because a harness and the billing route are not necessarily the same
thing. Provider metadata is marked as coming from source metadata, source
configuration, or being unavailable. `SessionKey` combines source and session
ID and is used for stable conversation identity.

`TokenDataGranularity` distinguishes:

- `requestEvent`: dated records suitable for period totals and charts.
- `lifetimeSessionModelAggregate`: source totals that are shown in lifetime
  and aggregate views but are excluded from dated charts and period totals.

### Source adapters

All adapters conform to `TokenUsageParser` and return `SourceImportResult`:

- `TokenParser` parses Claude Code assistant JSONL lines and extracts usage
  from `message.usage`.
- `ZCodeTokenParser` reads completed rows from `model_usage` and session
  metadata from the ZCode SQLite database. Reasoning tokens are folded into
  output tokens.
- `HermesTokenParser` reads `session_model_usage` and `sessions` from
  Hermes. It preserves multiple models and billing providers as lifetime
  aggregates.
- `CodexTokenParser` reads rollout `session_meta`, `turn_context`, and
  `event_msg/token_count` records. It uses the latest model/provider context
  for each token event and folds reasoning output into output tokens.
- `DeepSeekHarnessTokenParser` reads one JSON aggregate per DeepSeek Harness
  session and uses configured model/provider metadata.

Parsers run concurrently in a task group. A source result includes records,
conversation titles, source identity, completion time, and a status of
`succeeded`, `missing`, or `failed`.

### Service and refresh flow

`TokenService` is the main actor-isolated observable service shared by every
scene. On startup it loads the last committed cache snapshot, then refreshes
all parsers in the background. Refresh requests are coalesced so overlapping
requests do not run concurrently. A timer requests refresh every 60 seconds.

Each successful source import is upserted into `UsageRepository`. Stable record
identities make repeated imports idempotent and allow changed aggregate rows to
replace earlier values. Missing or failed sources retain their last-known
records while their freshness/error status is exposed to the UI.

If the persistent SwiftData container cannot be opened, the service falls back
to an in-memory repository for the current launch and exposes the cache error.

### Persistence

SwiftData stores three app-owned models:

- `CachedUsageRecord`: normalized token records with unique stable identities.
- `CachedConversation`: source-qualified conversation metadata and activity.
- `CachedSourceSyncState`: schema version, source identity, refresh times,
  status, and error details.

The current schema is `TakarPakaiSchemaV1`. `rebuildCache()` clears only this
derived cache; it never deletes or rewrites the original harness data.

### Query and UI layers

`UsageQuery` provides calendar-aware, exclusive-end period ranges and derives
dashboard, daily, provider, model, session, conversation, and detail results
from an immutable `UsageSnapshot`. The SwiftUI views consume the same
`TokenService` instance:

- `TakarPakaiApp.swift`: app lifecycle, shared service, scenes, and activation.
- `MenuBarView.swift`: compact menu bar dashboard, refresh, launch-at-login,
  settings, quit, and open-window actions.
- `MainWindowView.swift`: Home and Conversations navigation.
- `HomeView.swift`: period dashboard, provider chart, totals, and recent usage.
- `SettingsView.swift`: launch-at-login, version, cache/source status, and
  refresh controls.

## Project layout

```text
TakarPakai/
├── TakarPakaiApp.swift          # App, scenes, lifecycle, shared service
├── Models/
│   ├── TokenUsage.swift         # Normalized records and source/provider types
│   └── PersistenceModels.swift  # SwiftData cache schema and sync state
├── Services/
│   ├── TokenUsageParser.swift   # Parser protocol and common import contract
│   ├── TokenParser.swift        # Claude Code JSONL adapter
│   ├── ZCodeTokenParser.swift   # ZCode SQLite adapter
│   ├── HermesTokenParser.swift  # Hermes SQLite adapter
│   ├── CodexTokenParser.swift   # Codex rollout JSONL adapter
│   ├── DeepSeekHarnessTokenParser.swift # DeepSeek session JSON adapter
│   ├── TokenService.swift       # Refresh orchestration and published state
│   ├── UsageRepository.swift    # SwiftData persistence actor
│   └── UsageQuery.swift         # Period, dashboard, and conversation queries
├── Views/
│   ├── MenuBarView.swift
│   ├── MainWindowView.swift
│   ├── HomeView.swift
│   └── SettingsView.swift
├── TakarPakaiTests/             # XCTest parser, query, and repository tests
├── project.yml                  # XcodeGen project definition
├── Makefile                     # Build, run, install, release, clean
└── .github/workflows/release.yml # Signed and notarized tag releases
```

## Requirements

- macOS 14.0 or later.
- Xcode 15.0 or later for local development. The release workflow selects the
  configured Xcode version on its macOS runner.
- XcodeGen if you need to regenerate `TakarPakai.xcodeproj` from `project.yml`.

## Build and run

```bash
# Generate the Xcode project when project.yml changed
make generate

# Build Debug
make build

# Build and open the app
make run

# Copy the Debug app to /Applications
make install

# Open the generated project in Xcode
make xcode

# Build a Release configuration without code signing
make release

# Remove build products and Takar Pakai derived data
make clean
```

The Xcode scheme is `TakarPakai`. The application target is `TakarPakai` and
the unit-test target is `TakarPakaiTests`.

## Test harness

Tests use XCTest and run through the shared Xcode scheme. They cover:

- Claude and Codex JSONL parsing, including token deltas and malformed lines.
- ZCode and Hermes SQLite parsing, provider metadata, and aggregate semantics.
- DeepSeek Harness session JSON parsing, titles, and missing/malformed files.
- Calendar period boundaries, stable source-qualified session keys, mixed-model
  conversations, provider reconciliation, aggregate-only handling, charts,
  filters, and token formatting.
- SwiftData repository idempotency, changed-row replacement, missing-source
  retention, and cache rebuild behavior.

Run the tests with Xcode or directly with `xcodebuild`:

```bash
xcodebuild test -scheme TakarPakai -destination 'platform=macOS'
```

The parser tests use temporary SQLite databases, temporary DeepSeek JSON
directories, and the checked-in Codex rollout fixture at
`TakarPakaiTests/Fixtures/codex-rollout-fixture.jsonl`.

## Release harness

Pushing a tag matching `v*` starts `.github/workflows/release.yml`. GitHub
Actions on macOS archives the app with a Developer ID certificate, notarizes it
with `xcrun notarytool`, staples and validates the ticket, assesses the app with
`spctl`, packages a ZIP, and publishes a GitHub release.

The workflow expects these repository secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `KEYCHAIN_PASSWORD`

Certificates and passwords remain in the CI secret store and are not committed
to the repository.

## Data and privacy

Takar Pakai reads local harness history from the paths above and stores its
normalized cache in the app's local SwiftData container. It does not write to
those harness databases or JSONL files. “All Time” means all records currently
available in local history and does not include deleted history, other devices,
or account billing data.

## License

MIT
