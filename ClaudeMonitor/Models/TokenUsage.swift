import Foundation

struct TokenUsage: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
    let projectPath: String

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var displayModelName: String {
        ModelInfo.displayName(for: model)
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case model
        case inputTokens
        case outputTokens
        case cacheCreationTokens
        case cacheReadTokens
        case sessionId
        case projectPath
    }
}

struct ModelTokenUsage: Identifiable {
    let id = UUID()
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var displayName: String {
        ModelInfo.displayName(for: model)
    }
}

struct SessionTokenUsage: Identifiable {
    let id = UUID()
    let sessionId: String
    let title: String?
    let projectPath: String
    let model: String
    let firstTimestamp: Date
    let lastTimestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return projectDisplayName
    }

    /// Last path component of the project, human-readable.
    var projectDisplayName: String {
        let cleaned = projectPath.replacingOccurrences(of: "-", with: "/")
        return (cleaned as NSString).lastPathComponent
    }

    /// Format session timestamps relative to now, e.g. "2h ago".
    func relativeTimestamp(now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastTimestamp, relativeTo: now)
    }
}

struct ModelInfo {
    static func displayName(for model: String) -> String {
        if model.contains("opus") {
            if model.contains("4-6") || model.contains("4.6") {
                return "Opus 4.6"
            } else if model.contains("4-5") || model.contains("4.5") {
                return "Opus 4.5"
            }
            return "Opus"
        } else if model.contains("sonnet") {
            if model.contains("4-6") || model.contains("4.6") {
                return "Sonnet 4.6"
            } else if model.contains("4-5") || model.contains("4.5") {
                return "Sonnet 4.5"
            } else if model.contains("3-5") || model.contains("3.5") {
                return "Sonnet 3.5"
            }
            return "Sonnet"
        } else if model.contains("haiku") {
            if model.contains("4-5") || model.contains("4.5") {
                return "Haiku 4.5"
            } else if model.contains("3-5") || model.contains("3.5") {
                return "Haiku 3.5"
            }
            return "Haiku"
        }
        return model
    }

    static func color(for model: String) -> String {
        if model.contains("opus") {
            return "purple"
        } else if model.contains("sonnet") {
            return "blue"
        } else if model.contains("haiku") {
            return "orange"
        }
        return "gray"
    }
}

struct DailyTokenUsage: Identifiable {
    let id = UUID()
    let date: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct TokenStats {
    let daily: Int
    let weekly: Int
    let monthly: Int
    let weeklyBreakdown: [DailyTokenUsage]
    let modelBreakdown: [ModelTokenUsage]
    let dailyModelBreakdown: [ModelTokenUsage]
    let weeklyModelBreakdown: [ModelTokenUsage]
    let monthlyModelBreakdown: [ModelTokenUsage]
    let dailySessionBreakdown: [SessionTokenUsage]
    let weeklySessionBreakdown: [SessionTokenUsage]
    let monthlySessionBreakdown: [SessionTokenUsage]

    static var empty: TokenStats {
        TokenStats(
            daily: 0,
            weekly: 0,
            monthly: 0,
            weeklyBreakdown: [],
            modelBreakdown: [],
            dailyModelBreakdown: [],
            weeklyModelBreakdown: [],
            monthlyModelBreakdown: [],
            dailySessionBreakdown: [],
            weeklySessionBreakdown: [],
            monthlySessionBreakdown: []
        )
    }
}

struct AssistantMessage: Codable {
    let type: String
    let timestamp: String?
    let message: MessageContent?
    let sessionId: String?
    let cwd: String?
    let gitBranch: String?

    struct MessageContent: Codable {
        let model: String?
        let usage: Usage?
    }

    struct Usage: Codable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }
}

/// Represents the `ai-title` line emitted once per session file.
struct SessionTitleMessage: Codable {
    let type: String
    let sessionId: String?
    let aiTitle: String?
}
