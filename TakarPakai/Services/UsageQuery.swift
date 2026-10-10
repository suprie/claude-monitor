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

enum ConversationSort: String, CaseIterable, Sendable {
    case recent = "Recent activity"
    case tokens = "Token usage"
}

struct ConversationFilter: Sendable {
    var period: UsagePeriod = .allTime
    var search = ""
    var source: TokenSource?
    var provider: BillingProvider?
    var model: String?
    var sort: ConversationSort = .recent
}

struct ConversationSummary: Identifiable, Sendable {
    let key: SessionKey
    let title: String?
    let projectPath: String
    let providers: [BillingProvider]
    let models: [String]
    let firstTimestamp: Date
    let lastTimestamp: Date
    let totalTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let hasRequestEvents: Bool
    let hasAggregateRows: Bool

    var id: SessionKey { key }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let project = projectPath.hasPrefix("/") ? (projectPath as NSString).lastPathComponent : projectPath
        return project.isEmpty ? key.sessionId : project
    }

    var sourceQualifiedTitle: String { "\(key.source.displayName) · \(displayTitle)" }
    var providerLabel: String {
        providers.count > 1 ? "Multiple providers" : (providers.first?.displayName ?? BillingProvider.unknown.displayName)
    }
    var modelLabel: String {
        models.count > 1 ? "Multiple models" : (models.first.map(ModelInfo.displayName(for:)) ?? "Unknown")
    }
}

struct ConversationTokenBreakdown: Identifiable, Sendable {
    let model: String
    let provider: BillingProvider
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let isAggregate: Bool

    var id: String { "\(provider.rawValue):\(model):\(isAggregate)" }
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens }
    var modelLabel: String { ModelInfo.displayName(for: model) }
}

struct ConversationDetail: Sendable {
    let summary: ConversationSummary
    let selectedPeriod: UsagePeriod
    let selectedPeriodRecords: [TokenUsage]
    let lifetimeBreakdown: [ConversationTokenBreakdown]
    let selectedPeriodBreakdown: [ConversationTokenBreakdown]

    var lifetimeTotal: Int { summary.totalTokens }
    var selectedPeriodTotal: Int { selectedPeriodRecords.reduce(0) { $0 + $1.totalTokens } }
    var requestEvents: [TokenUsage] { selectedPeriodRecords.filter { $0.granularity == .requestEvent } }
    var aggregateRows: [ConversationTokenBreakdown] { lifetimeBreakdown.filter(\.isAggregate) }
    var hasReliableTimeline: Bool { !requestEvents.isEmpty }
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

    func conversations(in filter: ConversationFilter, from snapshot: UsageSnapshot, now: Date = Date()) -> [ConversationSummary] {
        let periodRecords = records(in: filter.period, from: snapshot, now: now)
        let grouped = Dictionary(grouping: periodRecords) { $0.sessionKey }

        return grouped.compactMap { key, records in
            guard filter.source == nil || filter.source == key.source else { return nil }
            let matchingRecords = records.filter {
                (filter.provider == nil || $0.provider == filter.provider) &&
                (filter.model == nil || $0.model == filter.model)
            }
            guard !matchingRecords.isEmpty else { return nil }

            let sorted = matchingRecords.sorted { $0.timestamp < $1.timestamp }
            let title = snapshot.titles[key]
            let projectPath = sorted.last(where: { !$0.projectPath.isEmpty })?.projectPath ?? ""
            let summary = makeSummary(key: key, title: title, records: sorted, projectPath: projectPath)
            let searchText = "\(summary.displayTitle) \(projectPath) \(key.sessionId) \(key.source.displayName)".lowercased()
            guard filter.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchText.contains(filter.search.lowercased()) else { return nil }
            return summary
        }
        .sorted {
            switch filter.sort {
            case .recent: return $0.lastTimestamp > $1.lastTimestamp
            case .tokens: return $0.totalTokens > $1.totalTokens
            }
        }
    }

    func conversation(for key: SessionKey, period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> ConversationDetail? {
        let lifetime = snapshot.records.filter { $0.sessionKey == key }
        guard !lifetime.isEmpty else { return nil }
        let sorted = lifetime.sorted { $0.timestamp < $1.timestamp }
        let summary = makeSummary(key: key, title: snapshot.titles[key], records: sorted,
                                  projectPath: sorted.last(where: { !$0.projectPath.isEmpty })?.projectPath ?? "")
        let periodRecords = records(in: period, from: UsageSnapshot(records: lifetime, titles: snapshot.titles), now: now)
        return ConversationDetail(
            summary: summary,
            selectedPeriod: period,
            selectedPeriodRecords: periodRecords,
            lifetimeBreakdown: breakdown(sorted),
            selectedPeriodBreakdown: breakdown(periodRecords)
        )
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

    private func makeSummary(key: SessionKey, title: String?, records: [TokenUsage], projectPath: String) -> ConversationSummary {
        ConversationSummary(
            key: key, title: title, projectPath: projectPath,
            providers: records.map(\.provider).removingDuplicates().sorted { $0.rawValue < $1.rawValue },
            models: records.map(\.model).removingDuplicates().sorted(),
            firstTimestamp: records.map(\.timestamp).min() ?? .distantPast,
            lastTimestamp: records.map(\.timestamp).max() ?? .distantPast,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens },
            inputTokens: records.reduce(0) { $0 + $1.inputTokens },
            outputTokens: records.reduce(0) { $0 + $1.outputTokens },
            cacheCreationTokens: records.reduce(0) { $0 + $1.cacheCreationTokens },
            cacheReadTokens: records.reduce(0) { $0 + $1.cacheReadTokens },
            hasRequestEvents: records.contains { $0.granularity == .requestEvent },
            hasAggregateRows: records.contains { $0.granularity == .lifetimeSessionModelAggregate }
        )
    }

    private func breakdown(_ records: [TokenUsage]) -> [ConversationTokenBreakdown] {
        struct Key: Hashable { let model: String; let provider: BillingProvider; let isAggregate: Bool }
        struct Totals { var input = 0; var output = 0; var read = 0; var create = 0 }
        var values: [Key: Totals] = [:]
        for record in records {
            let key = Key(model: record.model, provider: record.provider, isAggregate: record.granularity == .lifetimeSessionModelAggregate)
            var total = values[key, default: Totals()]
            total.input += record.inputTokens; total.output += record.outputTokens
            total.read += record.cacheReadTokens; total.create += record.cacheCreationTokens
            values[key] = total
        }
        return values.map { key, value in
            ConversationTokenBreakdown(model: key.model, provider: key.provider,
                                       inputTokens: value.input, outputTokens: value.output,
                                       cacheReadTokens: value.read, cacheCreationTokens: value.create,
                                       isAggregate: key.isAggregate)
        }.sorted { $0.totalTokens > $1.totalTokens }
    }
}

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
