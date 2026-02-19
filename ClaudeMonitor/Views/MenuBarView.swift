import SwiftUI
import Charts

struct MenuBarView: View {
    @EnvironmentObject var tokenService: TokenService
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @State private var selectedPeriod: TimePeriod = .daily

    enum TimePeriod: String, CaseIterable {
        case daily = "Today"
        case weekly = "Week"
        case monthly = "Month"
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
