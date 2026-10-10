# Token Monitor main app plan

Status: proposed · Created: 2026-10-10

Build a full macOS app where opening Token Monitor shows usage across providers, and selecting a conversation explains its token usage and estimated cost. Keep the menu bar as a quick summary and entry point. Each phase should be a separate, reviewable change that leaves the app usable.

## Product shape

- **Home:** selected-period token totals, daily usage graph colored by provider, provider totals, and recent conversations. Add estimated cost once pricing is available.
- **Conversations:** searchable history with source, provider, model(s), project, activity time, tokens, and eventually estimated cost.
- **Conversation detail:** lifetime totals, selected-period totals, model/provider breakdown, token categories, and an explanation of estimated cost.
- **Settings:** launch at login, source availability, and pricing configuration.
- **Menu bar:** today's usage, refresh, and an Open Token Monitor action.

Start with Today, This Week, This Month, and All Time. “All Time” means all locally available records, not deleted history or usage on other devices. Add a custom date range only after these presets work consistently.

## SwiftData cache and refresh flow

Use SwiftData as a local persistent cache of normalized usage and conversation metadata. Source JSONL files and SQLite databases remain authoritative. The main window and menu bar share one repository and the same committed cache snapshot.

On launch, load the last successful cached snapshot immediately, then refresh from the sources in the background. Keep showing that snapshot while a refresh is running. After a successful import, save the refreshed records and source sync metadata together, then update the visible totals, charts, and conversation details. A failed refresh keeps the last good data visible and marks the affected source as stale.

Persist usage records, conversation metadata, and per-source sync state (last successful refresh, import/schema version, and source-file identity where needed). Preserve source, provider, model, token categories, timestamps, and data granularity. Keep chart aggregates derived initially; if cost results are cached later, invalidate them when usage or pricing versions change. Keep the store local with cloud sync disabled.

Use stable source-qualified keys to upsert records. An updated Hermes aggregate replaces its previous value instead of being appended as another event. Reimporting unchanged history must not increase totals. Only reconcile deletions after a complete successful read of the affected source; an unavailable source or incomplete read must never look like an empty dataset. Cached records retained after source loss are shown as last-known data with their freshness visible.

Start with the existing 60-second refresh and manual refresh. Incremental imports and file-change triggers can follow after correctness and profiling. Run imports through a serialized background persistence worker using its own model context; publish immutable results to the UI after commits. Prevent overlapping imports and advance any import checkpoint only after its corresponding records are saved.

## What the code already provides

`ClaudeMonitorApp.swift` creates a `MenuBarExtra` and Settings scene, but no main window. `Info.plist` sets `LSUIElement` to true. `TokenService` reads four parsers every 60 seconds and builds daily, weekly, monthly, model, and session totals. Swift Charts is already used in the menu bar.

The main gaps are a window, reusable historical queries, provider identity, and pricing. The current session accumulator groups only by session ID and retains one model; a conversation can actually contain multiple models. Records and aggregate rows currently use generated UUIDs, which are unsuitable for persistent selection across refreshes.

`TokenSource` describes the recording application (Claude, Codex, ZCode, Hermes), not necessarily the billing provider. ZCode reads `provider_id` but does not preserve it separately. Hermes documents billing-provider aggregates but currently omits that field from its query. Hermes also exposes session/model aggregates stamped with `last_seen`, which cannot support an exact daily history by themselves.

## Before implementation

The working tree contains an in-progress ClaudeMonitor → TokenMonitor rename and unresolved project-file changes. Establish a buildable baseline while preserving that work. Align the Xcode target, scheme, Makefile, and test module import with the final naming. This is an implementation prerequisite, not a reason to change those files during planning.

## Small delivery phases

### Phase 1 — Open a real app window

Scope:
- Add a main window with Home and Conversations navigation; reuse the existing Settings scene.
- Show the existing token summary on Home as the first useful screen.
- Adopt normal Dock/app activation behavior and add Open Token Monitor to the menu bar.
- Explicit launch and Dock reopen show/focus the window. Launch at login starts quietly; closing the window keeps monitoring active.

Done when: opening the app shows Home, repeated opens focus the existing window, and menu bar monitoring continues after closing it. Verify these lifecycle behaviors manually.

Primary files: `ClaudeMonitorApp.swift`, `Info.plist`, `MenuBarView.swift`; new main-window and navigation views.

### Phase 2 — Make usage queries reliable

Scope:
- Retain a shared usage snapshot rather than exposing only the current preset aggregates.
- Introduce stable record identities and conversation keys using `(source, sessionId)`; use the same keys for titles and selection.
- Keep model-level records within conversations instead of assigning all tokens to one model.
- Normalize token categories per source: verify whether cached input is included in input and reasoning is included in output before adding either again. Treat cumulative counters and repeated events according to their actual semantics.
- Add reusable period queries, including All Time, with consistent local-calendar boundaries and an exclusive end date.

Done when: fixture totals reconcile across the menu bar and queries; identical session IDs from different sources stay separate; a mixed-model session preserves both models; refresh keeps selection stable. Add focused aggregation and normalization tests. Document any corrected totals that differ from the old menu bar.

Primary files: `TokenUsage.swift`, `TokenService.swift`, the four parsers; new query/aggregation types.

### Phase 3 — Identify billing providers

Scope:
- Store source and provider separately. Preserve provider metadata where available and retain its provenance.
- Use explicit provider mapping only when supported by source metadata/configuration; model names alone do not establish the billing route.
- Keep unresolved records under Unknown provider, with their source still visible. Never silently discard them.
- Carry data granularity: request/event data versus lifetime session/model aggregates.

Done when: provider totals plus Unknown reconcile to normalized token totals, and a Hermes or ZCode conversation can contain more than one provider. Verify metadata extraction with parser fixtures.

Primary files: models, parser protocol, source parsers, aggregation types.

### Phase 3a — Persist and read the SwiftData cache

Scope:
- Define versioned SwiftData models for usage records, conversations, and source sync state, using the stable identities from phase 2 and provider metadata from phase 3.
- Add a shared usage repository and local model container. Route menu bar and main-app queries through this repository.
- Import a complete source snapshot with idempotent upserts; replace changed aggregate rows and commit source freshness metadata with the records.
- Read cached data on startup so previous usage is available before parsing finishes. Retain the cache freshness timestamp rather than presenting startup as a successful source refresh.
- Define schema migration and cache rebuild behavior. A rebuild clears only the app-owned derived cache, never the original source data or pricing overrides; expose failures instead of silently deleting the store.

Done when: a second launch shows saved usage immediately; importing the same fixture twice leaves totals unchanged; changing one aggregate updates its existing row; queries match the normalized source fixtures. Verify persistence across container reopen, migration, and failed saves with a temporary test store.

Primary files: new SwiftData models, UsageRepository, persistence worker, container setup; `TokenService.swift`.

### Phase 3b — Refresh the cache while the app is open

Scope:
- Load the cache first, then schedule background refresh on startup, every 60 seconds, and on manual refresh.
- Serialize refreshes, coalesce repeated requests, and keep parsing/persistence work off the UI thread.
- Add source-level import results so successful reads, missing sources, and failures are distinguishable before cache reconciliation.
- Commit each successful source import atomically; retain failed sources' last good records and show their individual freshness/error state.
- Update Home, conversation lists/details, and the menu bar from the same committed repository revision, preserving active selection.

Done when: new source usage appears without reopening the app; cached charts stay visible during refresh; a source failure leaves its last-known usage intact; repeated refresh requests do not duplicate records or create concurrent imports. Verify recovery after a failed import and restart before a commit completes.

Primary files: `TokenService.swift`, parser result types, UsageRepository, persistence worker, shared refresh status.

### Phase 4 — Deliver the Home token dashboard

Scope:
- Add period controls, total/input/output/cache cards, and a daily stacked bar graph colored by provider.
- Add a provider totals table and a stable legend; fill missing event-level days with zero.
- Selecting a provider filters the dashboard; selecting a day shows its exact breakdown.
- Show coarse aggregate-only usage separately. If a source has no dated history, show its lifetime totals without pretending they occurred on `last_seen`.
- Include loading, no-history, and partial-data states, plus last refresh time.

Done when: users can compare token usage across providers; graph and table agree for the same scope; unavailable historical detail is clearly explained. Verify against a known multi-provider fixture.

Primary files: new Home/dashboard views; query layer and SwiftData repository from phases 2–3b.

### Phase 5 — Browse all conversations

Scope:
- Build a full conversation table from available local history.
- Search title/project and filter by period, source, provider, and model.
- Sort by recent activity or token usage; use “Multiple models/providers” where appropriate.
- Selecting a conversation opens its detail destination. Show source-qualified titles and identifiers consistently.

Done when: a user can find an old conversation and open it; table totals reflect the filters; active selection survives refresh. Verify filtering and selection behavior.

Primary files: new Conversations view and conversation query types.

### Phase 6 — Explain conversation token usage

Scope:
- Show conversation title, project, source, providers, activity dates, lifetime totals, and selected-period totals.
- Break down input, output, cache read, and cache creation by model/provider.
- Show usage events over time only for sources that supply event-level data; show aggregate rows for other sources.
- Add a simple route back to the filtered conversation list.

Done when: the conversation total equals its breakdown, mixed-model conversations remain accurate, and aggregate-only sources do not display an invented request timeline.

Primary files: new ConversationDetail view; shared query types.

### Phase 7 — Add a tested pricing engine

Scope:
- Add a local, versioned rate catalog keyed by billing provider, exact model, token category, and effective date. Verify supported rates against official sources during implementation and store the source URL and verification date.
- Calculate costs from normalized model-level records using decimal arithmetic, then aggregate them into conversations.
- Handle supported cache tiers, context tiers, or other modifiers explicitly. If required billing metadata is unavailable, expose that uncertainty instead of choosing a rate silently.
- Return known estimates, partial estimates, and unavailable estimates. Unknown models/providers are not zero-cost usage.
- Preserve the rate version used so an estimate can be explained and reproduced. Start with USD.

Done when: hand-calculated fixtures match for ordinary, cached, mixed-model, and missing-rate cases. Also test effective-date boundaries and rounding at display time.

Primary files: new PricingService, rate catalog, and cost result models. No cost UI in this phase.

### Phase 8 — Show conversation costs

Scope:
- Add estimated lifetime and selected-period cost to conversation detail.
- Show cost by model/provider and token category, with rates, rate version, and calculation coverage.
- Add settings for explicit rate overrides for custom providers/models; identify overrides in the explanation.
- Label estimates as API-equivalent estimates where actual billing is unknown. Subscription usage does not establish the amount charged for a conversation.

Done when: selecting a conversation answers “how much did this usage cost?” with an explainable estimate; incomplete pricing shows the known subtotal and unpriced usage rather than a misleading complete total.

Primary files: ConversationDetail view, `SettingsView.swift`, pricing configuration.

### Phase 9 — Add cost summaries across the app

Scope:
- Add estimated cost cards and a Tokens/Estimated Cost graph toggle to Home.
- Add provider cost totals and conversation cost columns/sorting.
- Apply the same filters, coverage rules, and pricing engine everywhere; totals link to their contributing conversations.
- Separate period estimates from lifetime estimates for coarse data, just as in the token graph.

Done when: Home, conversation list, and conversation detail reconcile for the same period/provider selection and disclose unpriced usage consistently.

Primary files: Home and Conversations views; query/cost aggregation layer.

### Phase 10 — Finish the everyday experience

Scope:
- Keep the menu bar compact and use it to open Home or a selected conversation.
- Distinguish missing sources from unreadable or malformed sources; report per-source refresh status.
- Profile representative large histories and SwiftData queries. Add targeted indexes and incremental parsing only where measurements justify them; handle appended partial JSONL lines, file truncation/replacement, and changed SQLite aggregates without losing or double-counting usage.
- Verify cache migration/rebuild, stale-source recovery, and startup with a missing or unreadable cache. Provide a visible temporary in-memory fallback if persistence cannot initialize, without overwriting the failed store.
- Verify resizing, keyboard navigation, accessibility labels, dark mode, launch-at-login, and empty installations.
- Update documentation to describe all supported sources and the limits of local-history and cost estimates.

Done when: a large-history fixture remains responsive, refresh does not duplicate usage, failed sources remain visible, and launch/reopen/close behavior passes the lifecycle checks from phase 1.

## Delivery checkpoints

1. **After phase 1:** Token Monitor behaves like a main app.
2. **After phase 3b:** Cached usage loads immediately and stays updated in the background.
3. **After phase 4:** Home shows reliable provider token comparisons.
4. **After phase 6:** Users can inspect all available conversations and their token breakdowns.
5. **After phase 8:** Individual conversations have explainable estimated costs.
6. **After phase 10:** Dashboard and conversation cost reporting are ready for everyday use.

Implement in order, including phases 3a and 3b, with one phase per PR where practical. If a phase requires multiple changes, separate the model/service work from its UI. Check off each phase only after its acceptance criteria pass. Avoid combining the phases into one release-sized refactor.

## Deferred work

Cloud sync, account billing imports, budget alerts, currency conversion, exports, full transcript browsing, and new usage-source integrations can follow the main-app release. The first version remains focused on local usage, provider comparisons, and conversation cost estimates.
