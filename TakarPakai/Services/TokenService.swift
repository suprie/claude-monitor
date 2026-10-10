import Foundation
import Combine

@MainActor
final class TokenService: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published var stats: TokenStats = .empty
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published private(set) var sourceStatuses: [SourceSyncStatus] = []
    @Published private(set) var cacheError: String?

    private let parsers: [TokenUsageParser]
    private let query: UsageQuery
    private let repository: UsageRepository?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false

    var todayTokensFormatted: String { TokenCountFormatter.string(stats.daily) }

    func dashboard(for period: UsagePeriod, provider: BillingProvider? = nil, now: Date = Date()) -> DashboardTokenUsage {
        query.dashboard(in: period, from: snapshot, provider: provider, now: now)
    }

    func conversations(in filter: ConversationFilter, now: Date = Date()) -> [ConversationSummary] {
        query.conversations(in: filter, from: snapshot, now: now)
    }

    func conversation(for key: SessionKey, period: UsagePeriod, now: Date = Date()) -> ConversationDetail? {
        query.conversation(for: key, period: period, from: snapshot, now: now)
    }

    init(parsers: [TokenUsageParser] = [TokenParser(), ZCodeTokenParser(), HermesTokenParser(), CodexTokenParser(), DeepSeekHarnessTokenParser()], calendar: Calendar = .current) {
        self.parsers = parsers
        self.query = UsageQuery(calendar: calendar)
        if let persistentRepository = try? UsageRepository() {
            self.repository = persistentRepository
            self.cacheError = nil
        } else if let memoryRepository = try? UsageRepository(inMemory: true) {
            self.repository = memoryRepository
            self.cacheError = "Persistent cache unavailable; using a temporary cache for this launch."
        } else {
            self.repository = nil
            self.cacheError = "Usage cache unavailable; data will remain in memory."
        }
        startAutoRefresh()
        Task { await bootstrap() }
    }

    func refresh() async {
        refreshRequested = true
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefreshLoop()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func rebuildCache() async {
        guard let repository else { return }
        do {
            try await repository.rebuildCache()
            apply(CachedStoreSnapshot(snapshot: UsageSnapshot(), sourceStatuses: []))
            await refresh()
        } catch {
            cacheError = error.localizedDescription
        }
    }

    private func bootstrap() async {
        if let repository, let cached = try? await repository.load() { apply(cached) }
        await refresh()
    }

    private func runRefreshLoop() async {
        while refreshRequested {
            refreshRequested = false
            await refreshOnce()
        }
    }

    private func refreshOnce() async {
        isLoading = true
        defer { isLoading = false }
        // Publish each source as soon as its actor finishes. A slow JSONL
        // source no longer blocks faster SQLite sources from appearing.
        await withTaskGroup(of: SourceImportResult.self) { group in
            for parser in parsers { group.addTask { await parser.parseSource() } }
            for await result in group {
                await importAndApply(result)
            }
        }
    }

    private func importAndApply(_ result: SourceImportResult) async {
        if let repository {
            do {
                try await repository.importSource(result)
            } catch {
                let failed = SourceImportResult.failed(source: result.source, error: error)
                try? await repository.importSource(failed)
            }
            if let cached = try? await repository.load() { apply(cached) }
            return
        }

        apply(result, to: snapshot)
    }

    /// Replaces only the completed source, preserving the last known data for
    /// sources that are still parsing or could not be read this time.
    private func apply(_ result: SourceImportResult, to current: UsageSnapshot) {
        var records = current.records
        var titles = current.titles
        var statuses = sourceStatuses

        if result.status == .succeeded {
            records.removeAll { $0.source == result.source }
            records.append(contentsOf: result.records)
            titles = titles.filter { $0.key.source != result.source }
            titles.merge(result.titles) { _, new in new }
        }

        let previousStatus = statuses.first { $0.source == result.source }
        let status = SourceSyncStatus(
            source: result.source,
            status: result.status,
            lastSuccessfulRefresh: result.status == .succeeded ? result.completedAt : previousStatus?.lastSuccessfulRefresh,
            lastAttemptedRefresh: result.completedAt,
            sourceIdentity: result.status == .succeeded ? result.sourceIdentity : previousStatus?.sourceIdentity,
            errorDescription: result.errorDescription
        )
        statuses.removeAll { $0.source == result.source }
        statuses.append(status)

        apply(CachedStoreSnapshot(
            snapshot: UsageSnapshot(records: records, titles: titles,
                                    lastSuccessfulRefresh: statuses.compactMap(\.lastSuccessfulRefresh).max()),
            sourceStatuses: statuses.sorted { $0.source.rawValue < $1.source.rawValue }
        ))
    }

    private func apply(_ cached: CachedStoreSnapshot) {
        snapshot = cached.snapshot
        stats = makeStats(from: cached.snapshot)
        sourceStatuses = cached.sourceStatuses
        lastUpdated = cached.snapshot.lastSuccessfulRefresh
    }

    private func makeStats(from snapshot: UsageSnapshot, now: Date = Date()) -> TokenStats {
        TokenStats(
            daily: query.total(in: .today, from: snapshot, now: now), weekly: query.total(in: .thisWeek, from: snapshot, now: now), monthly: query.total(in: .thisMonth, from: snapshot, now: now),
            weeklyBreakdown: query.daily(in: .thisWeek, from: snapshot, now: now), modelBreakdown: query.models(in: .allTime, from: snapshot, now: now),
            dailyModelBreakdown: query.models(in: .today, from: snapshot, now: now), weeklyModelBreakdown: query.models(in: .thisWeek, from: snapshot, now: now),
            monthlyModelBreakdown: query.models(in: .thisMonth, from: snapshot, now: now), dailySessionBreakdown: query.sessions(in: .today, from: snapshot, now: now),
            weeklySessionBreakdown: query.sessions(in: .thisWeek, from: snapshot, now: now), monthlySessionBreakdown: query.sessions(in: .thisMonth, from: snapshot, now: now)
        )
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    isolated deinit { refreshTimer?.invalidate(); refreshTask?.cancel() }
}
