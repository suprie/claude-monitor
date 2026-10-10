import Foundation

enum UsagePeriod: String, CaseIterable, Sendable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    func range(now: Date, calendar: Calendar) -> Range<Date> {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return start..<calendar.date(byAdding: .day, value: 1, to: start)!
        case .thisWeek:
            let start = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            )!
            return start..<calendar.date(byAdding: .day, value: 7, to: start)!
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return start..<calendar.date(byAdding: .month, value: 1, to: start)!
        case .allTime:
            return Date.distantPast..<Date.distantFuture
        }
    }
}

struct UsageSnapshot: Sendable {
    let records: [TokenUsage]
    let titles: [SessionKey: String]
    let createdAt: Date
    let lastSuccessfulRefresh: Date?

    init(records: [TokenUsage] = [], titles: [SessionKey: String] = [:], createdAt: Date = Date(), lastSuccessfulRefresh: Date? = nil) {
        self.records = records
        self.titles = titles
        self.createdAt = createdAt
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
    }
}

struct ProviderTokenUsage: Identifiable {
    let provider: BillingProvider
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var id: String { provider.id }
    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

struct DailyProviderTokenUsage: Identifiable {
    let date: Date
    let provider: BillingProvider
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var id: String { "\(date.timeIntervalSince1970):\(provider.id)" }
    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

struct AggregateProviderTokenUsage: Identifiable {
    let source: TokenSource
    let provider: BillingProvider
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var id: String { "\(source.rawValue):\(provider.id)" }
    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

struct DashboardTokenUsage {
    let period: UsagePeriod
    let datedRecords: [TokenUsage]
    let daily: [DailyProviderTokenUsage]
    let providers: [ProviderTokenUsage]
    let aggregateProviders: [AggregateProviderTokenUsage]

    var totalTokens: Int { datedRecords.reduce(0) { $0 + $1.totalTokens } }
    var inputTokens: Int { datedRecords.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { datedRecords.reduce(0) { $0 + $1.outputTokens } }
    var cacheCreationTokens: Int { datedRecords.reduce(0) { $0 + $1.cacheCreationTokens } }
    var cacheReadTokens: Int { datedRecords.reduce(0) { $0 + $1.cacheReadTokens } }
    var aggregateTotalTokens: Int { aggregateProviders.reduce(0) { $0 + $1.totalTokens } }

    var hasDatedHistory: Bool { !datedRecords.isEmpty }
    var hasAggregateOnlyUsage: Bool { !aggregateProviders.isEmpty }
}

struct UsageQuery {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func records(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [TokenUsage] {
        let range = period.range(now: now, calendar: calendar)
        return snapshot.records.filter {
            range.contains($0.timestamp) && (period == .allTime || $0.granularity == .requestEvent)
        }
    }

    func total(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> Int {
        records(in: period, from: snapshot, now: now).reduce(0) { $0 + $1.totalTokens }
    }

    func models(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [ModelTokenUsage] {
        aggregateModels(records(in: period, from: snapshot, now: now))
    }

    func providers(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [ProviderTokenUsage] {
        aggregateProviderTotals(records(in: period, from: snapshot, now: now))
    }

    func dashboard(
        in period: UsagePeriod,
        from snapshot: UsageSnapshot,
        provider: BillingProvider? = nil,
        now: Date = Date()
    ) -> DashboardTokenUsage {
        let datedRecords = records(in: period, from: snapshot, now: now)
            .filter { $0.granularity == .requestEvent && (provider == nil || $0.provider == provider) }
        let aggregateRecords = snapshot.records
            .filter { $0.granularity == .lifetimeSessionModelAggregate && (provider == nil || $0.provider == provider) }

        return DashboardTokenUsage(
            period: period,
            datedRecords: datedRecords,
            daily: dailyByProvider(period: period, records: datedRecords, now: now),
            providers: aggregateProviderTotals(datedRecords),
            aggregateProviders: aggregateProviderTotalsBySource(aggregateRecords)
        )
    }

    func sessions(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [SessionTokenUsage] {
        var grouped: [SessionKey: [TokenUsage]] = [:]
        for record in records(in: period, from: snapshot, now: now) {
            grouped[record.sessionKey, default: []].append(record)
        }

        return grouped.map { key, records in
            let sorted = records.sorted { $0.timestamp < $1.timestamp }
            let first = sorted[0]
            return SessionTokenUsage(
                sessionId: key.sessionId,
                title: snapshot.titles[key],
                projectPath: sorted.last(where: { !$0.projectPath.isEmpty })?.projectPath ?? first.projectPath,
                model: sorted.map(\.model).removingDuplicates().joined(separator: ", "),
                source: key.source,
                providers: records.map(\.provider).removingDuplicates().sorted { $0.rawValue < $1.rawValue },
                firstTimestamp: sorted.map(\.timestamp).min()!,
                lastTimestamp: sorted.map(\.timestamp).max()!,
                inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                cacheCreationTokens: records.reduce(0) { $0 + $1.cacheCreationTokens },
                cacheReadTokens: records.reduce(0) { $0 + $1.cacheReadTokens },
                models: aggregateModels(records)
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }

    func daily(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [DailyTokenUsage] {
        let range = period.range(now: now, calendar: calendar)
        let grouped = Dictionary(grouping: records(in: period, from: snapshot, now: now)) {
            calendar.startOfDay(for: $0.timestamp)
        }
        var day = calendar.startOfDay(for: range.lowerBound)
        var result: [DailyTokenUsage] = []
        while day < range.upperBound {
            let records = grouped[day] ?? []
            result.append(DailyTokenUsage(
                date: day,
                inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                cacheCreationTokens: records.reduce(0) { $0 + $1.cacheCreationTokens },
                cacheReadTokens: records.reduce(0) { $0 + $1.cacheReadTokens }
            ))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func dailyByProvider(period: UsagePeriod, records: [TokenUsage], now: Date) -> [DailyProviderTokenUsage] {
        guard let range = dailyRange(for: period, records: records, now: now) else { return [] }
        struct Totals { var input = 0; var output = 0; var create = 0; var read = 0 }
        struct DayProvider: Hashable { let day: Date; let provider: BillingProvider }
        let grouped = Dictionary(grouping: records) {
            DayProvider(day: calendar.startOfDay(for: $0.timestamp), provider: $0.provider)
        }
        var result: [DailyProviderTokenUsage] = []
        var day = range.lowerBound
        while day < range.upperBound {
            let providers = Set(records.map(\.provider))
            for provider in providers.sorted(by: { $0.rawValue < $1.rawValue }) {
                let totals = grouped[DayProvider(day: day, provider: provider), default: []].reduce(into: Totals()) { value, record in
                    value.input += record.inputTokens
                    value.output += record.outputTokens
                    value.create += record.cacheCreationTokens
                    value.read += record.cacheReadTokens
                }
                result.append(DailyProviderTokenUsage(
                    date: day,
                    provider: provider,
                    inputTokens: totals.input,
                    outputTokens: totals.output,
                    cacheCreationTokens: totals.create,
                    cacheReadTokens: totals.read
                ))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func dailyRange(for period: UsagePeriod, records: [TokenUsage], now: Date) -> Range<Date>? {
        if period == .allTime {
            guard let first = records.map(\.timestamp).min(), let last = records.map(\.timestamp).max() else { return nil }
            let start = calendar.startOfDay(for: first)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))!
            return start..<end
        }
        return period.range(now: now, calendar: calendar)
    }

    private func aggregateProviderTotals(_ records: [TokenUsage]) -> [ProviderTokenUsage] {
        struct Totals { var input = 0; var output = 0; var create = 0; var read = 0 }
        var totals: [BillingProvider: Totals] = [:]
        for record in records {
            var value = totals[record.provider, default: Totals()]
            value.input += record.inputTokens
            value.output += record.outputTokens
            value.create += record.cacheCreationTokens
            value.read += record.cacheReadTokens
            totals[record.provider] = value
        }
        return totals.map { provider, value in
            ProviderTokenUsage(provider: provider, inputTokens: value.input, outputTokens: value.output,
                               cacheCreationTokens: value.create, cacheReadTokens: value.read)
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

    private func aggregateProviderTotalsBySource(_ records: [TokenUsage]) -> [AggregateProviderTokenUsage] {
        struct Key: Hashable { let source: TokenSource; let provider: BillingProvider }
        struct Totals { var input = 0; var output = 0; var create = 0; var read = 0 }
        var totals: [Key: Totals] = [:]
        for record in records {
            let key = Key(source: record.source, provider: record.provider)
            var value = totals[key, default: Totals()]
            value.input += record.inputTokens
            value.output += record.outputTokens
            value.create += record.cacheCreationTokens
            value.read += record.cacheReadTokens
            totals[key] = value
        }
        return totals.map { key, value in
            AggregateProviderTokenUsage(source: key.source, provider: key.provider,
                                        inputTokens: value.input, outputTokens: value.output,
                                        cacheCreationTokens: value.create, cacheReadTokens: value.read)
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

    private func aggregateModels(_ records: [TokenUsage]) -> [ModelTokenUsage] {
        struct Totals { var input = 0; var output = 0; var create = 0; var read = 0 }
        struct ModelKey: Hashable { let source: TokenSource; let provider: BillingProvider; let model: String }
        var totals: [ModelKey: Totals] = [:]
        for record in records {
            let key = ModelKey(source: record.source, provider: record.provider, model: record.model)
            var value = totals[key, default: Totals()]
            value.input += record.inputTokens
            value.output += record.outputTokens
            value.create += record.cacheCreationTokens
            value.read += record.cacheReadTokens
            totals[key] = value
        }
        return totals.map { key, value in
            return ModelTokenUsage(
                model: key.model, source: key.source, provider: key.provider,
                inputTokens: value.input, outputTokens: value.output,
                cacheCreationTokens: value.create, cacheReadTokens: value.read
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }
}

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
