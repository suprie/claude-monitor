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

        let allUsage = await parser.parseAllTokenUsage()
        let calculatedStats = calculateStats(from: allUsage)

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

    private func calculateStats(from usages: [TokenUsage]) -> TokenStats {
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

        return TokenStats(
            daily: daily,
            weekly: weekly,
            monthly: monthly,
            weeklyBreakdown: weeklyBreakdown,
            modelBreakdown: modelBreakdown,
            dailyModelBreakdown: dailyModels,
            weeklyModelBreakdown: weeklyModels,
            monthlyModelBreakdown: monthlyModels
        )
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
