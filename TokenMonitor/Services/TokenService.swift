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

    var todayTokensFormatted: String { formatTokenCount(stats.daily) }

    init(parsers: [TokenUsageParser] = [TokenParser(), ZCodeTokenParser(), HermesTokenParser(), CodexTokenParser()], calendar: Calendar = .current) {
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
        let task = Task { @MainActor [weak self] in await self?.runRefreshLoop() }
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
        let results = await Self.collectSourceResults(from: parsers)

        if let repository {
            for result in results {
                do { try await repository.importSource(result) }
                catch { try? await repository.importSource(.failed(source: result.source, error: error)) }
            }
            if let cached = try? await repository.load() { apply(cached) }
        } else {
            let successful = results.filter { $0.status == .succeeded }
            let records = successful.flatMap(\.records)
            let titles = successful.reduce(into: [SessionKey: String]()) { result, source in
                result.merge(source.titles) { _, new in new }
            }
            let newSnapshot = UsageSnapshot(records: records, titles: titles, lastSuccessfulRefresh: successful.map(\.completedAt).max())
            let statuses = results.map { result in
                SourceSyncStatus(source: result.source, status: result.status,
                                 lastSuccessfulRefresh: result.status == .succeeded ? result.completedAt : nil,
                                 lastAttemptedRefresh: result.completedAt, sourceIdentity: result.sourceIdentity,
                                 errorDescription: result.errorDescription)
            }
            apply(CachedStoreSnapshot(snapshot: newSnapshot, sourceStatuses: statuses))
        }
    }

    private static func collectSourceResults(from parsers: [TokenUsageParser]) async -> [SourceImportResult] {
        await withTaskGroup(of: SourceImportResult.self) { group in
            for parser in parsers { group.addTask { await parser.parseSource() } }
            var result: [SourceImportResult] = []
            for await sourceResult in group { result.append(sourceResult) }
            return result.sorted { $0.source.rawValue < $1.source.rawValue }
        }
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

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    isolated deinit { refreshTimer?.invalidate(); refreshTask?.cancel() }
}
