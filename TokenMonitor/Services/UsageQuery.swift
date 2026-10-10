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

    init(records: [TokenUsage] = [], titles: [SessionKey: String] = [:], createdAt: Date = Date()) {
        self.records = records
        self.titles = titles
        self.createdAt = createdAt
    }
}

struct UsageQuery {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func records(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [TokenUsage] {
        let range = period.range(now: now, calendar: calendar)
        return snapshot.records.filter { range.contains($0.timestamp) }
    }

    func total(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> Int {
        records(in: period, from: snapshot, now: now).reduce(0) { $0 + $1.totalTokens }
    }

    func models(in period: UsagePeriod, from snapshot: UsageSnapshot, now: Date = Date()) -> [ModelTokenUsage] {
        aggregateModels(records(in: period, from: snapshot, now: now))
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

    private func aggregateModels(_ records: [TokenUsage]) -> [ModelTokenUsage] {
        struct Totals { var input = 0; var output = 0; var create = 0; var read = 0 }
        var totals: [String: Totals] = [:]
        for record in records {
            let key = "\(record.source.rawValue):\(record.model)"
            var value = totals[key, default: Totals()]
            value.input += record.inputTokens
            value.output += record.outputTokens
            value.create += record.cacheCreationTokens
            value.read += record.cacheReadTokens
            totals[key] = value
        }
        return totals.map { key, value in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            return ModelTokenUsage(
                model: parts[1], source: TokenSource(rawValue: parts[0])!,
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
