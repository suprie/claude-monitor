import Foundation
import Combine

@MainActor
class TokenService: ObservableObject {
    @Published var stats: TokenStats = .empty
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private let parser = TokenParser()
    private var refreshTimer: Timer?

    var todayTokensFormatted: String {
        formatTokenCount(stats.daily)
    }

    init() {
        Task {
            await refresh()
        }
        startAutoRefresh()
    }

    func refresh() async {
        isLoading = true

        async let allUsageTask = parser.parseAllTokenUsage()
        async let titlesTask = parser.parseSessionTitles()

        let allUsage = await allUsageTask				
        let titles = await titlesTask
        let calculatedStats = calculateStats(from: allUsage, sessionTitles: titles)

        stats = calculatedStats
        lastUpdated = Date()
        isLoading = false
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

        // Model breakdowns
        var allTimeModelBreakdown: [String: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var dailyModelBreakdown: [String: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var weeklyModelBreakdown: [String: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]
        var monthlyModelBreakdown: [String: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)] = [:]

        // Session breakdowns keyed by sessionId
        var dailySessionBreakdown: [String: SessionAccumulator] = [:]
        var weeklySessionBreakdown: [String: SessionAccumulator] = [:]
        var monthlySessionBreakdown: [String: SessionAccumulator] = [:]

        for usage in usages {
            let usageDay = calendar.startOfDay(for: usage.timestamp)
            let model = usage.model

            // All time model breakdown
            let allTimeExisting = allTimeModelBreakdown[model] ?? (0, 0, 0, 0)
            allTimeModelBreakdown[model] = (
                allTimeExisting.input + usage.inputTokens,
                allTimeExisting.output + usage.outputTokens,
                allTimeExisting.cacheCreate + usage.cacheCreationTokens,
                allTimeExisting.cacheRead + usage.cacheReadTokens
            )

            // Daily
            if usage.timestamp >= startOfToday {
                daily += usage.totalTokens

                let existing = dailyModelBreakdown[model] ?? (0, 0, 0, 0)
                dailyModelBreakdown[model] = (
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

                let weeklyExisting = weeklyModelBreakdown[model] ?? (0, 0, 0, 0)
                weeklyModelBreakdown[model] = (
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

                let existing = monthlyModelBreakdown[model] ?? (0, 0, 0, 0)
                monthlyModelBreakdown[model] = (
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
        var firstTimestamp: Date = .distantFuture
        var lastTimestamp: Date = .distantPast
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
    }

    private func accumulateSession(_ breakdown: inout [String: SessionAccumulator], usage: TokenUsage) {
        var entry = breakdown[usage.sessionId] ?? SessionAccumulator()
        entry.projectPath = usage.projectPath
        entry.model = usage.model
        entry.firstTimestamp = min(entry.firstTimestamp, usage.timestamp)
        entry.lastTimestamp = max(entry.lastTimestamp, usage.timestamp)
        entry.inputTokens += usage.inputTokens
        entry.outputTokens += usage.outputTokens
        entry.cacheCreationTokens += usage.cacheCreationTokens
        entry.cacheReadTokens += usage.cacheReadTokens
        breakdown[usage.sessionId] = entry
    }

    private func convertToSessionUsageArray(_ breakdown: [String: SessionAccumulator], titles: [String: String]) -> [SessionTokenUsage] {
        breakdown
            .map { sessionId, acc in
                SessionTokenUsage(
                    sessionId: sessionId,
                    title: titles[sessionId],
                    projectPath: acc.projectPath,
                    model: acc.model,
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

    private func convertToModelUsageArray(_ breakdown: [String: (input: Int, output: Int, cacheCreate: Int, cacheRead: Int)]) -> [ModelTokenUsage] {
        breakdown
            .map { model, tokens in
                ModelTokenUsage(
                    model: model,
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

    deinit {
        refreshTimer?.invalidate()
    }
}
