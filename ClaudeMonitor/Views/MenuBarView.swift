import SwiftUI
import Charts

struct MenuBarView: View {
    @EnvironmentObject var tokenService: TokenService
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @State private var selectedPeriod: TimePeriod = .daily
    @State private var sessionSortOption: SessionSortOption = .recent

    enum TimePeriod: String, CaseIterable {
        case daily = "Today"
        case weekly = "Week"
        case monthly = "Month"
    }

    /// How the per-session breakdown list is ordered.
    enum SessionSortOption: String, CaseIterable {
        /// Most recently updated session first.
        case recent = "Recent"
        /// Highest total token usage first.
        case tokens = "Tokens"

        var systemImage: String {
            switch self {
            case .recent: return "clock"
            case .tokens: return "number"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Claude Token Monitor")
                    .font(.headline)
                Spacer()
                if tokenService.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // Stats Overview
            VStack(spacing: 8) {
                StatRow(title: "Today", value: tokenService.stats.daily, icon: "sun.max.fill")
                StatRow(title: "This Week", value: tokenService.stats.weekly, icon: "calendar")
                StatRow(title: "This Month", value: tokenService.stats.monthly, icon: "calendar.badge.clock")
            }

            Divider()

            // Model Breakdown
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("By Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                ModelBreakdownView(models: currentModelBreakdown)
            }

            Divider()

            // Session Breakdown
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("By Session")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(sortedSessionBreakdown.count) session\(sortedSessionBreakdown.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    SessionSortMenu(selection: $sessionSortOption)
                }

                SessionBreakdownView(sessions: sortedSessionBreakdown)
            }

            Divider()

            // Weekly Chart
            if !tokenService.stats.weeklyBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly Usage")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    WeeklyChart(data: tokenService.stats.weeklyBreakdown)
                        .frame(height: 100)
                }

                Divider()
            }

            // Footer
            HStack {
                if let lastUpdated = tokenService.lastUpdated {
                    Text("Updated: \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task {
                        await tokenService.refresh()
                    }
                }
                .buttonStyle(.borderless)
            }

            Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var currentModelBreakdown: [ModelTokenUsage] {
        switch selectedPeriod {
        case .daily:
            return tokenService.stats.dailyModelBreakdown
        case .weekly:
            return tokenService.stats.weeklyModelBreakdown
        case .monthly:
            return tokenService.stats.monthlyModelBreakdown
        }
    }

    private var currentSessionBreakdown: [SessionTokenUsage] {
        switch selectedPeriod {
        case .daily:
            return tokenService.stats.dailySessionBreakdown
        case .weekly:
            return tokenService.stats.weeklySessionBreakdown
        case .monthly:
            return tokenService.stats.monthlySessionBreakdown
        }
    }

    /// Sessions for the selected period, re-sorted per the user's sort choice.
    private var sortedSessionBreakdown: [SessionTokenUsage] {
        switch sessionSortOption {
        case .recent:
            return currentSessionBreakdown.sorted { $0.lastTimestamp > $1.lastTimestamp }
        case .tokens:
            return currentSessionBreakdown
        }
    }
}

struct ModelBreakdownView: View {
    let models: [ModelTokenUsage]

    var body: some View {
        if models.isEmpty {
            Text("No usage data")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 6) {
                ForEach(models) { model in
                    ModelRow(model: model)
                }
            }
        }
    }
}

struct ModelRow: View {
    let model: ModelTokenUsage

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(modelColor)
                .frame(width: 8, height: 8)

            Text(model.displayName)
                .font(.system(.caption, design: .default))
                .foregroundColor(.primary)

            Spacer()

            Text(formatTokens(model.totalTokens))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var modelColor: Color {
        let colorName = ModelInfo.color(for: model.model)
        switch colorName {
        case "purple": return .purple
        case "blue": return .blue
        case "orange": return .orange
        default: return .gray
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

struct SessionBreakdownView: View {
    let sessions: [SessionTokenUsage]

    /// Number of sessions shown before the list collapses.
    private let previewLimit = 5
    @State private var isExpanded = false

    var body: some View {
        if sessions.isEmpty {
            Text("No usage data")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 6) {
                ForEach(visibleSessions) { session in
                    SessionRow(session: session)
                }

                if sessions.count > previewLimit {
                    Button(isExpanded ? "Show less" : "Show \(sessions.count - previewLimit) more") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var visibleSessions: [SessionTokenUsage] {
        isExpanded ? sessions : Array(sessions.prefix(previewLimit))
    }
}

/// Compact menu for switching the session list sort order.
struct SessionSortMenu: View {
    @Binding var selection: MenuBarView.SessionSortOption

    var body: some View {
        Menu {
            ForEach(MenuBarView.SessionSortOption.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Label(option.rawValue, systemImage: option.systemImage)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2)
                Text(selection.rawValue)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct SessionRow: View {
    let session: SessionTokenUsage
    @State var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 8))
                    .foregroundColor(sessionColor)
                Text(session.displayName)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .help(session.title ?? "No title")
                
                SourceBadge(source: session.source)
                Spacer(minLength: 0)
                Text(formatTokens(session.totalTokens))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            HStack(spacing: 6) {
                TokenBadge(label: "in", value: session.inputTokens, color: .blue)
                TokenBadge(label: "out", value: session.outputTokens, color: .green)
                if session.cacheReadTokens > 0 {
                    TokenBadge(label: "cache", value: session.cacheReadTokens, color: .orange)
                }
                Spacer(minLength: 0)
                Text(session.relativeTimestamp())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text(session.sessionId)
                    .font(.caption2)

                Text(session.projectPath)
                    .font(.caption2)
                    .help(session.projectPath)

            }
        }
        .padding(.vertical, 2)
    }

    private var sessionColor: Color {
        let colorName = ModelInfo.color(for: session.model)
        switch colorName {
        case "purple": return .purple
        case "blue": return .blue
        case "orange": return .orange
        default: return .gray
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

/// Compact inline token display, e.g. "in 12.3K".
struct TokenBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(color)
            Text(compactFormat(value))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func compactFormat(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// Small tag distinguishing Claude, ZCode, and Hermes sessions in a merged list.
struct SourceBadge: View {
    let source: TokenSource

    var body: some View {
        Text(source.badgeText)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
    }

    private var color: Color {
        switch source {
        case .claude: return .blue
        case .zcode: return .teal
        case .hermes: return .indigo
        case .codex: return .green
        }
    }
}

struct StatRow: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatTokens(value))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

struct WeeklyChart: View {
    let data: [DailyTokenUsage]

    var body: some View {
        Chart(data) { day in
            BarMark(
                x: .value("Day", day.weekday),
                y: .value("Tokens", day.totalTokens)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(formatAxisValue(intValue))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private func formatAxisValue(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        } else if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
    }
}

#Preview {
    MenuBarView()
        .environmentObject(TokenService())
}
