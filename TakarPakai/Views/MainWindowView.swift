import SwiftUI
import AppKit
import Charts

struct MainWindowView: View {
    @State private var selection: MainNavigationItem? = .home

    var body: some View {
        NavigationSplitView {
            List(MainNavigationItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
            .navigationTitle("Takar Pakai")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .home {
            case .home:
                HomeView()
            case .conversations:
                ConversationsView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

enum MainNavigationItem: String, CaseIterable, Hashable, Identifiable {
    case home
    case conversations

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Home"
        case .conversations: return "Conversations"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "chart.bar.xaxis"
        case .conversations: return "bubble.left.and.bubble.right"
        }
    }
}

struct ConversationsView: View {
    @EnvironmentObject private var tokenService: TokenService
    @State private var filter = ConversationFilter()
    @State private var selectedKey: SessionKey?

    var body: some View {
        let summaries = tokenService.conversations(in: filter)
        let providers = availableProviders
        let models = availableModels

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ConversationFilters(filter: $filter, providers: providers, models: models)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if summaries.isEmpty {
                    ContentUnavailableView("No conversations", systemImage: "magnifyingglass",
                                           description: Text("Try a different period or search term."))
                } else {
                    Table(summaries, selection: $selectedKey) {
                        TableColumn("Conversation") { summary in
                            HStack(alignment: .bottom, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.sourceQualifiedTitle).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(summary.modelLabel)
                                        Text("·").foregroundStyle(.tertiary)
                                        Text(summary.totalTokens, format: .number).monospacedDigit()
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    Text(summary.key.sessionId).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(summary.lastTimestamp, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .width(min: 280)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text("\(summaries.count) conversations")
                    Spacer()
                    Text("Filtered total: \(summaries.reduce(0) { $0 + $1.totalTokens }, format: .number) tokens")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
            }
            .navigationTitle("Conversations")
            .searchable(text: $filter.search, placement: .toolbar, prompt: "Search title, project, or ID")
            .toolbar {
                ToolbarItem {
                    Button { Task { await tokenService.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(tokenService.isLoading)
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            Group {
                if let selectedKey, let detail = tokenService.conversation(for: selectedKey, period: filter.period) {
                    ConversationDetailView(detail: detail) {
                        self.selectedKey = nil
                    }
                } else {
                    ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Choose a conversation to inspect its token usage."))
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
    }

    private var availableProviders: [BillingProvider] {
        Array(Set(tokenService.snapshot.records.map(\.provider))).sorted { $0.displayName < $1.displayName }
    }

    private var availableModels: [String] {
        Array(Set(tokenService.snapshot.records.map(\.model))).sorted()
    }
}

struct ConversationFilters: View {
    @Binding var filter: ConversationFilter
    let providers: [BillingProvider]
    let models: [String]

    var body: some View {
        HStack {
            Picker("Period", selection: $filter.period) {
                ForEach(UsagePeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Source", selection: Binding(get: { filter.source?.rawValue ?? "all" }, set: { filter.source = $0 == "all" ? nil : TokenSource(rawValue: $0) })) {
                Text("All sources").tag("all")
                ForEach(TokenSource.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.menu)

            Picker("Provider", selection: Binding(get: { filter.provider?.id ?? "all" }, set: { filter.provider = $0 == "all" ? nil : BillingProvider(rawValue: $0) })) {
                Text("All providers").tag("all")
                ForEach(providers) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.menu)

            Picker("Model", selection: Binding(get: { filter.model ?? "all" }, set: { filter.model = $0 == "all" ? nil : $0 })) {
                Text("All models").tag("all")
                ForEach(models, id: \.self) { Text(ModelInfo.displayName(for: $0)).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Sort", selection: $filter.sort) {
                ForEach(ConversationSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
        .controlSize(.small)
    }
}

struct ConversationDetailView: View {
    let detail: ConversationDetail
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.summary.sourceQualifiedTitle).font(.title.bold())
                    Text("\(detail.summary.key.source.displayName) · \(detail.summary.key.sessionId)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !detail.summary.projectPath.isEmpty { Text(detail.summary.projectPath).font(.subheadline).foregroundStyle(.secondary) }
                    Text("\(detail.summary.firstTimestamp, format: .dateTime.month().day().year()) – \(detail.summary.lastTimestamp, format: .dateTime.month().day().year())")
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    ConversationTotalCard(title: "Lifetime", value: detail.lifetimeTotal, color: .blue)
                    ConversationTotalCard(title: detail.selectedPeriod.rawValue, value: detail.selectedPeriodTotal, color: .indigo)
                }

                ConversationBreakdownPanel(title: "Lifetime breakdown", rows: detail.lifetimeBreakdown)
                ConversationBreakdownPanel(title: "Selected-period breakdown", rows: detail.selectedPeriodBreakdown)

                if detail.hasReliableTimeline {
                    ConversationTimeline(records: detail.requestEvents)
                } else {
                    ConversationBreakdownPanel(title: "Usage history", rows: detail.aggregateRows)
                    Text("This source provides lifetime session/model aggregates, not request-level events. The timeline is intentionally unavailable; aggregate rows are not assigned to dates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .navigationTitle("Conversation detail")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) { Label("Back to conversations", systemImage: "chevron.left") }
            }
        }
    }
}

struct ConversationTotalCard: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(value, format: .number).font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ConversationBreakdownPanel: View {
    let title: String
    let rows: [ConversationTokenBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            if rows.isEmpty {
                Text("No usage in this period.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Model / provider")
                    Spacer(); Text("Input").frame(width: 78, alignment: .trailing); Text("Output").frame(width: 78, alignment: .trailing)
                    Text("Cache").frame(width: 78, alignment: .trailing); Text("Total").frame(width: 90, alignment: .trailing)
                }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.modelLabel)
                            Text("\(row.provider.displayName)\(row.isAggregate ? " · aggregate" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.inputTokens, format: .number).frame(width: 78, alignment: .trailing)
                        Text(row.outputTokens, format: .number).frame(width: 78, alignment: .trailing)
                        Text(row.cacheReadTokens + row.cacheCreationTokens, format: .number).frame(width: 78, alignment: .trailing)
                        Text(row.totalTokens, format: .number).frame(width: 90, alignment: .trailing).bold()
                    }
                    Divider()
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        // The detail view is hosted in a flexible split-view column. Keep
        // this panel at its content height so rows are not pushed to the
        // bottom of a tall, apparently empty card.
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ConversationTimeline: View {
    let records: [TokenUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage events over time").font(.title2.bold())
            Chart(records) { record in
                BarMark(x: .value("Time", record.timestamp), y: .value("Tokens", record.totalTokens))
                    .foregroundStyle(by: .value("Provider", record.provider.displayName))
            }
            .chartYAxis { AxisMarks() }
            .frame(minHeight: 240)
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
