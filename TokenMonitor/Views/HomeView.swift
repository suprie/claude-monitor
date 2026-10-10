import Charts
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var tokenService: TokenService
    @State private var selectedPeriod: UsagePeriod = .thisWeek
    @State private var selectedProviderID = "all"
    @State private var selectedDay: Date?

    var body: some View {
        let allDashboard = tokenService.dashboard(for: selectedPeriod)
        let selectedProvider = selectedProviderID == "all" ? nil : BillingProvider(rawValue: selectedProviderID)
        let dashboard = tokenService.dashboard(for: selectedPeriod, provider: selectedProvider)
        let providers = allDashboard.providers.map(\.provider) + allDashboard.aggregateProviders.map(\.provider)
        let availableProviders = Array(Set(providers)).sorted { $0.displayName < $1.displayName }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HomeHeader(lastUpdated: tokenService.lastUpdated, isLoading: tokenService.isLoading, cacheError: tokenService.cacheError)
                DashboardControls(
                    period: $selectedPeriod,
                    providerID: $selectedProviderID,
                    providers: availableProviders
                )

                if tokenService.isLoading && tokenService.snapshot.records.isEmpty {
                    DashboardLoadingState()
                } else if !dashboard.hasDatedHistory && !dashboard.hasAggregateOnlyUsage {
                    DashboardEmptyState()
                } else {
                    DashboardTokenCards(dashboard: dashboard)
                    DailyProviderChart(
                        data: dashboard.daily,
                        providers: availableProviders,
                        selectedDay: $selectedDay,
                        calendar: Calendar.current
                    )
                    ProviderTotalsSection(
                        providers: dashboard.providers,
                        aggregateProviders: dashboard.aggregateProviders
                    )
                    if let selectedDay {
                        SelectedDaySection(
                            date: selectedDay,
                            data: dashboard.daily,
                            calendar: Calendar.current
                        )
                    }
                }

                if hasPartialData(statuses: tokenService.sourceStatuses) {
                    DashboardDataNotice(statuses: tokenService.sourceStatuses)
                }
                SourceHealthSection(statuses: tokenService.sourceStatuses)
            }
            .padding(28)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await tokenService.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(tokenService.isLoading)
            }
        }
    }

    private func hasPartialData(statuses: [SourceSyncStatus]) -> Bool {
        statuses.contains { $0.status != .succeeded && $0.lastSuccessfulRefresh != nil }
    }
}

struct DashboardControls: View {
    @Binding var period: UsagePeriod
    @Binding var providerID: String
    let providers: [BillingProvider]

    var body: some View {
        HStack {
            Picker("Period", selection: $period) {
                ForEach(UsagePeriod.allCases, id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430)

            Spacer()

            Picker("Provider", selection: $providerID) {
                Text("All providers").tag("all")
                ForEach(providers) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .frame(width: 180)
        }
    }
}

struct DashboardLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading local usage history…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct DashboardEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No usage history",
            systemImage: "chart.bar.xaxis",
            description: Text("No dated token events or lifetime aggregate usage are available for this installation yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct DashboardTokenCards: View {
    let dashboard: DashboardTokenUsage

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            DashboardTokenCard(title: "Total", value: dashboard.totalTokens, color: .blue)
            DashboardTokenCard(title: "Input", value: dashboard.inputTokens, color: .indigo)
            DashboardTokenCard(title: "Output", value: dashboard.outputTokens, color: .orange)
            DashboardTokenCard(title: "Cache", value: dashboard.cacheCreationTokens + dashboard.cacheReadTokens, color: .mint)
        }
    }
}

struct DashboardTokenCard: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DailyProviderChart: View {
    let data: [DailyProviderTokenUsage]
    let providers: [BillingProvider]
    @Binding var selectedDay: Date?
    let calendar: Calendar

    var body: some View {
        DashboardPanel(title: "Daily usage", systemImage: "chart.bar.xaxis") {
            if data.isEmpty {
                Text("No dated request history is available for this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Tokens", item.totalTokens)
                    )
                    .foregroundStyle(by: .value("Provider", item.provider.displayName))
                }
                .chartForegroundStyleScale(
                    domain: providers.map(\.displayName),
                    range: providers.map { ProviderChartStyle.color(for: $0) }
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(TokenCountFormatter.string(count))
                            } else if let count = value.as(Double.self) {
                                Text(TokenCountFormatter.string(count))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDay)
                .frame(minHeight: 250)

                ProviderLegend(providers: providers)
            }
        }
    }
}

struct ProviderLegend: View {
    let providers: [BillingProvider]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(providers) { provider in
                Label(provider.displayName, systemImage: "circle.fill")
                    .foregroundStyle(ProviderChartStyle.color(for: provider))
                    .font(.caption)
            }
        }
    }
}

struct ProviderTotalsSection: View {
    let providers: [ProviderTokenUsage]
    let aggregateProviders: [AggregateProviderTokenUsage]

    var body: some View {
        DashboardPanel(title: "Provider totals", systemImage: "square.stack.3d.up") {
            if providers.isEmpty {
                Text("No dated provider totals are available for this period.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ProviderTableHeader()
                    ForEach(providers) { provider in
                        ProviderTableRow(provider: provider)
                    }
                }
            }

            if !aggregateProviders.isEmpty {
                Divider().padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lifetime aggregate-only usage")
                        .font(.headline)
                    Text("These sources provide totals but no dated request history, so they are not placed on the graph or attributed to last seen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(aggregateProviders) { aggregate in
                        HStack {
                            Circle().fill(ProviderChartStyle.color(for: aggregate.provider)).frame(width: 8, height: 8)
                            Text("\(aggregate.provider.displayName) · \(aggregate.source.displayName)")
                            Spacer()
                            Text(aggregate.totalTokens, format: .number).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}

struct ProviderTableHeader: View {
    var body: some View {
        HStack {
            Text("Provider")
            Spacer()
            Text("Input").frame(width: 90, alignment: .trailing)
            Text("Output").frame(width: 90, alignment: .trailing)
            Text("Cache").frame(width: 90, alignment: .trailing)
            Text("Total").frame(width: 100, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
    }
}

struct ProviderTableRow: View {
    let provider: ProviderTokenUsage

    var body: some View {
        HStack {
            Label(provider.provider.displayName, systemImage: "circle.fill")
                .foregroundStyle(ProviderChartStyle.color(for: provider.provider))
            Spacer()
            Text(provider.inputTokens, format: .number).frame(width: 90, alignment: .trailing)
            Text(provider.outputTokens, format: .number).frame(width: 90, alignment: .trailing)
            Text(provider.cacheCreationTokens + provider.cacheReadTokens, format: .number).frame(width: 90, alignment: .trailing)
            Text(provider.totalTokens, format: .number).frame(width: 100, alignment: .trailing).bold()
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}

struct SelectedDaySection: View {
    let date: Date
    let data: [DailyProviderTokenUsage]
    let calendar: Calendar

    var body: some View {
        let day = calendar.startOfDay(for: date)
        let rows = data.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.totalTokens > $1.totalTokens }

        DashboardPanel(title: "Selected day · \(day.formatted(.dateTime.month().day().year()))", systemImage: "calendar") {
            if rows.isEmpty {
                Text("No dated usage on this day.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Label(row.provider.displayName, systemImage: "circle.fill")
                            .foregroundStyle(ProviderChartStyle.color(for: row.provider))
                        Spacer()
                        Text("Input \(row.inputTokens, format: .number) · Output \(row.outputTokens, format: .number) · Cache \(row.cacheCreationTokens + row.cacheReadTokens, format: .number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.totalTokens, format: .number).monospacedDigit().bold()
                    }
                }
            }
        }
    }
}

struct DashboardDataNotice: View {
    let statuses: [SourceSyncStatus]

    var body: some View {
        let affected = statuses.filter { $0.status != .succeeded }.map { $0.source.displayName }.joined(separator: ", ")
        Label("Some sources are unavailable (\(affected)); showing their last-known data where available.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

struct DashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.semibold))
            content
        }
        .padding(20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

enum ProviderChartStyle {
    static func color(for provider: BillingProvider) -> Color {
        let palette: [Color] = [.blue, .purple, .orange, .green, .teal, .pink, .indigo, .mint]
        let hash = provider.id.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}

struct SourceHealthSection: View {
    let statuses: [SourceSyncStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source status")
                .font(.title2.weight(.semibold))

            if statuses.isEmpty {
                Text("No source refresh has completed yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(statuses) { status in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        Text(status.source.displayName)
                        Spacer()
                        Text(statusTitle(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if status.id != statuses.last?.id { Divider() }
                }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusColor(_ status: SourceSyncStatus) -> Color {
        switch status.status {
        case .succeeded: return .green
        case .missing: return .gray
        case .failed: return .red
        }
    }

    private func statusTitle(_ status: SourceSyncStatus) -> String {
        switch status.status {
        case .succeeded:
            if let date = status.lastSuccessfulRefresh {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
            }
            return "Available"
        case .missing:
            return status.lastSuccessfulRefresh == nil ? "Unavailable" : "Unavailable · last known data"
        case .failed:
            return status.errorDescription ?? "Refresh failed"
        }
    }
}

struct HomeHeader: View {
    let lastUpdated: Date?
    let isLoading: Bool
    let cacheError: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage overview")
                    .font(.largeTitle.weight(.semibold))
                Text("Token usage across your local coding sessions")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
            } else if let lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let cacheError {
            Label(cacheError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct UsageSummarySection: View {
    let daily: Int
    let weekly: Int
    let monthly: Int

    var body: some View {
        HStack(spacing: 16) {
            UsageCard(title: "Today", value: daily, systemImage: "sun.max.fill", color: .orange)
            UsageCard(title: "This Week", value: weekly, systemImage: "calendar", color: .blue)
            UsageCard(title: "This Month", value: monthly, systemImage: "calendar.badge.clock", color: .purple)
        }
    }
}

struct UsageCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ModelUsageOverviewSection: View {
    let daily: [ModelTokenUsage]
    let weekly: [ModelTokenUsage]
    let monthly: [ModelTokenUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage by model")
                .font(.title2.weight(.semibold))

            EqualSizeCardLayout(minimumCardWidth: 220, spacing: 16) {
                ModelPieChartCard(title: "Today", models: daily)
                ModelPieChartCard(title: "This Week", models: weekly)
                ModelPieChartCard(title: "This Month", models: monthly)
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Gives every card the same dimensions, including when cards wrap into rows.
struct EqualSizeCardLayout: Layout {
    let minimumCardWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? minimumCardWidth * CGFloat(subviews.count)
            + spacing * CGFloat(subviews.count - 1)
        let metrics = metrics(width: width, subviews: subviews)
        let rows = (subviews.count + metrics.columns - 1) / metrics.columns
        return CGSize(
            width: width,
            height: metrics.cardSize.height * CGFloat(rows) + spacing * CGFloat(rows - 1)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let metrics = metrics(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % metrics.columns) * (metrics.cardSize.width + spacing),
                    y: bounds.minY + CGFloat(index / metrics.columns) * (metrics.cardSize.height + spacing)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(metrics.cardSize)
            )
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> (columns: Int, cardSize: CGSize) {
        let columns = min(subviews.count, max(1, Int((width + spacing) / (minimumCardWidth + spacing))))
        let cardWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let cardProposal = ProposedViewSize(width: cardWidth, height: nil)
        let cardHeight = subviews.map { $0.sizeThatFits(cardProposal).height }.max() ?? 0
        return (columns, CGSize(width: cardWidth, height: cardHeight))
    }
}

struct ModelPieChartCard: View {
    let title: String
    let models: [ModelTokenUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if models.isEmpty {
                ContentUnavailableView("No usage", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
            } else {
                ZStack {
                    Chart(models, id: \.chartID) { model in
                        SectorMark(
                            angle: .value("Tokens", model.totalTokens),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(ModelChartStyle.color(for: model))
                    }
                    .frame(width: 170, height: 170)

                    VStack(spacing: 2) {
                        Text(models.reduce(0) { $0 + $1.totalTokens }, format: .number)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                ModelLegend(models: models)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ModelLegend: View {
    let models: [ModelTokenUsage]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
            ForEach(models, id: \.chartID) { model in
                Label {
                    Text("\(model.displayName) · \(model.provider.displayName) · \(model.source.displayName)")
                        .lineLimit(1)
                } icon: {
                    Circle()
                        .fill(ModelChartStyle.color(for: model))
                        .frame(width: 9, height: 9)
                }
                .font(.caption)
            }
        }
    }
}

enum ModelChartStyle {
    static func color(for model: ModelTokenUsage) -> Color {
        switch ModelInfo.color(for: model.model) {
        case "purple": return .purple
        case "blue": return .blue
        case "orange": return .orange
        case "teal": return .teal
        default:
            let palette: [Color] = [.pink, .green, .indigo, .cyan, .mint]
            let hash = model.chartID.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
            return palette[abs(hash) % palette.count]
        }
    }
}

struct RecentUsageSection: View {
    let sessions: [SessionTokenUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent conversations")
                .font(.title2.weight(.semibold))

            if sessions.isEmpty {
                Text("No conversations with usage in the current week.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(5)) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.displayName)
                                .lineLimit(1)
                            Text("\(session.source.displayName) · \(session.providerDisplayName) · \(session.relativeTimestamp())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.totalTokens, format: .number)
                            .monospacedDigit()
                    }
                    if session.id != sessions.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
