import Foundation
import Combine

@MainActor
final class TokenService: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published var stats: TokenStats = .empty
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private let parsers: [TokenUsageParser]
    private let query: UsageQuery
    private var refreshTimer: Timer?

    var todayTokensFormatted: String { formatTokenCount(stats.daily) }

    init(parsers: [TokenUsageParser] = [TokenParser(), ZCodeTokenParser(), HermesTokenParser(), CodexTokenParser()], calendar: Calendar = .current) {
        self.parsers = parsers
        self.query = UsageQuery(calendar: calendar)
        startAutoRefresh()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        async let records = Self.collectUsage(from: parsers)
        async let titles = Self.collectTitles(from: parsers)
        let newSnapshot = UsageSnapshot(records: await records, titles: await titles)
        snapshot = newSnapshot
        stats = makeStats(from: newSnapshot)
        lastUpdated = newSnapshot.createdAt
        isLoading = false
    }

    private static func collectUsage(from parsers: [TokenUsageParser]) async -> [TokenUsage] {
        await withTaskGroup(of: [TokenUsage].self) { group in
            for parser in parsers { group.addTask { await parser.parseAllTokenUsage() } }
            var result: [TokenUsage] = []
            for await batch in group { result.append(contentsOf: batch) }
            return result
        }
    }

    private static func collectTitles(from parsers: [TokenUsageParser]) async -> [SessionKey: String] {
        await withTaskGroup(of: [SessionKey: String].self) { group in
            for parser in parsers { group.addTask { await parser.parseSessionTitles() } }
            var result: [SessionKey: String] = [:]
            for await batch in group { result.merge(batch) { _, new in new } }
            return result
        }
    }

    private func makeStats(from snapshot: UsageSnapshot, now: Date = Date()) -> TokenStats {
        TokenStats(
            daily: query.total(in: .today, from: snapshot, now: now),
            weekly: query.total(in: .thisWeek, from: snapshot, now: now),
            monthly: query.total(in: .thisMonth, from: snapshot, now: now),
            weeklyBreakdown: query.daily(in: .thisWeek, from: snapshot, now: now),
            modelBreakdown: query.models(in: .allTime, from: snapshot, now: now),
            dailyModelBreakdown: query.models(in: .today, from: snapshot, now: now),
            weeklyModelBreakdown: query.models(in: .thisWeek, from: snapshot, now: now),
            monthlyModelBreakdown: query.models(in: .thisMonth, from: snapshot, now: now),
            dailySessionBreakdown: query.sessions(in: .today, from: snapshot, now: now),
            weeklySessionBreakdown: query.sessions(in: .thisWeek, from: snapshot, now: now),
            monthlySessionBreakdown: query.sessions(in: .thisMonth, from: snapshot, now: now)
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

    isolated deinit {
        refreshTimer?.invalidate()
    }
}
