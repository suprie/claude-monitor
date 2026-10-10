import Foundation
import Combine

@MainActor
class TokenService: ObservableObject {
    @Published var stats: TokenStats = .empty
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    /// All token-usage sources, queried concurrently on each refresh.
    /// New sources can be added here without touching the refresh logic.
    private let parsers: [TokenUsageParser]
    private var refreshTimer: Timer?

    var todayTokensFormatted: String {
        formatTokenCount(stats.daily)
    }

    init(parsers: [TokenUsageParser] = [
        TokenParser(),
        ZCodeTokenParser(),
        HermesTokenParser(),
        CodexTokenParser()
    ]) {
        self.parsers = parsers
        Task {
            await refresh()
        }
        startAutoRefresh()
    }

    func refresh() async {
        isLoading = true

        // Fan out across all parsers concurrently.
        async let usageTask = collectUsage()
        async let titlesTask = collectTitles()

        let allUsage = await usageTask
        let titles = await titlesTask
        let calculatedStats = calculateStats(from: allUsage, sessionTitles: titles)

        stats = calculatedStats
        lastUpdated = Date()
        isLoading = false
    }

    private func collectUsage() async -> [TokenUsage] {
        await withTaskGroup(of: [TokenUsage].self) { group in
            for parser in parsers {
                group.addTask { await parser.parseAllTokenUsage() }
            }
            var combined: [TokenUsage] = []
            for await batch in group {
                combined.append(contentsOf: batch)
            }
            return combined
        }
    }

    private func collectTitles() async -> [String: String] {
        await withTaskGroup(of: [String: String].self) { group in
            for parser in parsers {
                group.addTask { await parser.parseSessionTitles() }
            }
            var combined: [String: String] = [:]
            for await batch in group {
                combined.merge(batch) { _, new in new }
            }
            return combined
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    private func calculateStats(from usages: [TokenUsage], sessionTitles: [String: String]) -> TokenStats {
        let calendar = Calendar.current
        let now = Date()

        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var daily = 0
        var weekly = 0
        var monthly = 0
        var dailyBreakdown: [Date: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]

        // Model breakdowns, keyed by (model, source) so the same model name
        // from Claude and ZCode doesn't silently merge.
        var allTimeModelBreakdown: [ModelKey: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var dailyModelBreakdown: [ModelKey: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var weeklyModelBreakdown: [ModelKey: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var monthlyModelBreakdown: [ModelKey: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]

        // Session breakdowns keyed by sessionId
        var dailySessionBreakdown: [String: SessionAccumulator] = [:]
        var weeklySessionBreakdown: [String: SessionAccumulator] = [:]
        var monthlySessionBreakdown: [String: SessionAccumulator] = [:]

        for usage in usages {
            let usageDay = calendar.startOfDay(for: usage.timestamp)
            let modelKey = ModelKey(model: usage.model, source: usage.source)

            // All time model breakdown
            let allTimeExisting = allTimeModelBreakdown[modelKey] ?? (0, 0, 0, 0)
            allTimeModelBreakdown[modelKey] = (
                allTimeExisting.input + usage.inputTokens,
                allTimeExisting.output + usage.outputTokens,
                allTimeExisting.cacheCreate + usage.cacheCreationTokens,
                allTimeExisting.cacheRead + usage.cacheReadTokens
            )

            // Daily
            if usage.timestamp >= startOfToday {
                daily += usage.totalTokens

                let existing = dailyModelBreakdown[modelKey] ?? (0, 0, 0, 0)
                dailyModelBreakdown[modelKey] = (
                    existing.input + usage.inputTokens,
                    existing.output + usage.outputTokens,
                    existing.cacheCreate + usage.cacheCreationTokens,
                    existing.cacheRead + usage.cacheReadTokens
                )

                accumulateSession(&dailySessionBreakdown, usage: usage)
            }

            // Weekly
            if usage.timestamp >= startOfWeek {
                weekly += usage.totalTokens

                // Track daily breakdown for the week
                let existing = dailyBreakdown[usageDay] ?? (0, 0, 0, 0)
                dailyBreakdown[usageDay] = (
                    existing.input + usage.inputTokens,
                    existing.output + usage.outputTokens,
                    existing.cacheCreate + usage.cacheCreationTokens,
                    existing.cacheRead + usage.cacheReadTokens
                )

                let weeklyExisting = weeklyModelBreakdown[modelKey] ?? (0, 0, 0, 0)
                weeklyModelBreakdown[modelKey] = (
                    weeklyExisting.input + usage.inputTokens,
                    weeklyExisting.output + usage.outputTokens,
                    weeklyExisting.cacheCreate + usage.cacheCreationTokens,
                    weeklyExisting.cacheRead + usage.cacheReadTokens
                )

                accumulateSession(&weeklySessionBreakdown, usage: usage)
            }

            // Monthly
            if usage.timestamp >= startOfMonth {
                monthly += usage.totalTokens

                let existing = monthlyModelBreakdown[modelKey] ?? (0, 0, 0, 0)
                monthlyModelBreakdown[modelKey] = (
                    existing.input + usage.inputTokens,
                    existing.output + usage.outputTokens,
                    existing.cacheCreate + usage.cacheCreationTokens,
                    existing.cacheRead + usage.cacheReadTokens
                )

                accumulateSession(&monthlySessionBreakdown, usage: usage)
            }
        }

        // Convert daily breakdown to array sorted by date
        let weeklyBreakdown = dailyBreakdown
            .map { date, tokens in
                DailyTokenUsage(
                    date: date,
                    inputTokens: tokens.input,
                    outputTokens: tokens.output,
                    cacheCreationTokens: tokens.cacheCreate,
                    cacheReadTokens: tokens.cacheRead
                )
            }
            .sorted { $0.date < $1.date }

        // Convert model breakdowns to arrays sorted by total tokens
        let modelBreakdown = convertToModelUsageArray(allTimeModelBreakdown)
        let dailyModels = convertToModelUsageArray(dailyModelBreakdown)
        let weeklyModels = convertToModelUsageArray(weeklyModelBreakdown)
        let monthlyModels = convertToModelUsageArray(monthlyModelBreakdown)

        // Convert session breakdowns to arrays sorted by total tokens (most usage first)
        let dailySessions = convertToSessionUsageArray(dailySessionBreakdown, titles: sessionTitles)
        let weeklySessions = convertToSessionUsageArray(weeklySessionBreakdown, titles: sessionTitles)
        let monthlySessions = convertToSessionUsageArray(monthlySessionBreakdown, titles: sessionTitles)

        return TokenStats(
            daily: daily,
            weekly: weekly,
            monthly: monthly,
            weeklyBreakdown: weeklyBreakdown,
            modelBreakdown: modelBreakdown,
            dailyModelBreakdown: dailyModels,
            weeklyModelBreakdown: weeklyModels,
            monthlyModelBreakdown: monthlyModels,
            dailySessionBreakdown: dailySessions,
            weeklySessionBreakdown: weeklySessions,
            monthlySessionBreakdown: monthlySessions
        )
    }

    /// Per-session aggregation state while iterating usages.
    private struct SessionAccumulator {
        var projectPath: String = ""
        var model: String = "unknown"
        var source: TokenSource = .claude
        var firstTimestamp: Date = .distantFuture
        var lastTimestamp: Date = .distantPast
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
    }

    /// Compound key so per-model breakdowns keep Claude and ZCode apart even
    /// when they share a model id.
    private struct ModelKey: Hashable {
        let model: String
        let source: TokenSource
    }

    private func accumulateSession(_ breakdown: inout [String: SessionAccumulator], usage: TokenUsage) {
        var entry = breakdown[usage.sessionId] ?? SessionAccumulator()
        entry.projectPath = usage.projectPath
        entry.model = usage.model
        entry.source = usage.source
        entry.firstTimestamp = min(entry.firstTimestamp, usage.timestamp)
        entry.lastTimestamp = max(entry.lastTimestamp, usage.timestamp)
        entry.inputTokens += usage.inputTokens
        entry.outputTokens += usage.outputTokens
        entry.cacheCreationTokens += usage.cacheCreationTokens
        entry.cacheReadTokens += usage.cacheReadTokens
        breakdown[usage.sessionId] = entry
    }

    private func convertToSessionUsageArray(_ breakdown: [String: SessionAccumulator], titles: [String: String]) -> [SessionTokenUsage] {
        return breakdown
            .map { sessionId, acc in
                SessionTokenUsage(
                    sessionId: sessionId,
                    title: titles[sessionId],
                    projectPath: acc.projectPath,
                    model: acc.model,
                    source: acc.source,
                    firstTimestamp: acc.firstTimestamp,
                    lastTimestamp: acc.lastTimestamp,
                    inputTokens: acc.inputTokens,
                    outputTokens: acc.outputTokens,
                    cacheCreationTokens: acc.cacheCreationTokens,
                    cacheReadTokens: acc.cacheReadTokens
                )
            }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func convertToModelUsageArray(_ breakdown: [ModelKey: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)]) -> [ModelTokenUsage] {
        breakdown
            .map { key, tokens in
                ModelTokenUsage(
                    model: key.model,
                    source: key.source,
                    inputTokens: tokens.input,
                    outputTokens: tokens.output,
                    cacheCreationTokens: tokens.cacheCreate,
                    cacheReadTokens: tokens.cacheRead
                )
            }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }

    isolated deinit {
        refreshTimer?.invalidate()
    }
}
