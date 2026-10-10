import Charts
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var tokenService: TokenService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HomeHeader(lastUpdated: tokenService.lastUpdated, isLoading: tokenService.isLoading)
                UsageSummarySection(
                    daily: tokenService.stats.daily,
                    weekly: tokenService.stats.weekly,
                    monthly: tokenService.stats.monthly
                )
                ModelUsageOverviewSection(
                    daily: tokenService.stats.dailyModelBreakdown,
                    weekly: tokenService.stats.weeklyModelBreakdown,
                    monthly: tokenService.stats.monthlyModelBreakdown
                )
                RecentUsageSection(sessions: tokenService.stats.weeklySessionBreakdown)
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
}

struct HomeHeader: View {
    let lastUpdated: Date?
    let isLoading: Bool

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
                    Text("\(model.displayName) · \(model.source.displayName)")
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
                            Text("\(session.source.displayName) · \(session.relativeTimestamp())")
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
