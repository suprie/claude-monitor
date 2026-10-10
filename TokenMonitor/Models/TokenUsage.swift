import Foundation

/// Where a token-usage record originated: Claude (JSONL), ZCode (SQLite),
/// Hermes (SQLite), Codex (JSONL), or DeepSeek Harness (JSON cache).
enum TokenSource: String, Codable, CaseIterable, Sendable {
    case claude
    case zcode
    case hermes
    case codex
    case deepseekHarness = "deepseek-harness"

    /// Short uppercase tag for compact UI badges, e.g. "CC" / "ZC" / "HE".
    var badgeText: String {
        switch self {
        case .claude: return "CC"
        case .zcode: return "ZC"
        case .hermes: return "HE"
        case .codex: return "CX"
        case .deepseekHarness: return "DS"
        }
    }

    /// Human-readable label.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .zcode: return "ZCode"
        case .hermes: return "Hermes"
        case .codex: return "Codex"
        case .deepseekHarness: return "DeepSeek Harness"
        }
    }
}

/// The billing route for a usage record, independent of the recording app.
struct BillingProvider: Hashable, Codable, Sendable, Identifiable {
    let rawValue: String

    static let unknown = BillingProvider(rawValue: "unknown")

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = normalized.isEmpty ? Self.unknown.rawValue : normalized
    }

    init(rawValue: String?) {
        self.init(rawValue: rawValue ?? Self.unknown.rawValue)
    }

    var id: String { rawValue }

    var displayName: String {
        guard self != .unknown else { return "Unknown" }
        return rawValue.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ").capitalized
    }
}

enum ProviderMetadataProvenance: String, Codable, Sendable {
    case sourceMetadata
    case sourceConfiguration
    case unavailable
}

enum TokenDataGranularity: String, Codable, Sendable {
    case requestEvent
    case lifetimeSessionModelAggregate
}

struct SessionKey: Hashable, Codable, Identifiable, Sendable, CustomStringConvertible {
    let source: TokenSource
    let sessionId: String

    var id: String { description }
    var description: String { "\(source.rawValue):\(sessionId)" }
}

struct TokenUsage: Codable, Identifiable, Sendable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
    let projectPath: String
    let source: TokenSource
    let provider: BillingProvider
    /// The provider identifier exactly as supplied by the source, when one exists.
    let providerRawValue: String?
    let providerProvenance: ProviderMetadataProvenance
    let granularity: TokenDataGranularity

    init(
        timestamp: Date, model: String, inputTokens: Int, outputTokens: Int,
        cacheCreationTokens: Int, cacheReadTokens: Int, sessionId: String,
        projectPath: String, source: TokenSource, provider: BillingProvider = .unknown,
        providerRawValue: String? = nil,
        providerProvenance: ProviderMetadataProvenance = .unavailable,
        granularity: TokenDataGranularity = .requestEvent
    ) {
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.source = source
        self.provider = provider
        self.providerRawValue = providerRawValue
        self.providerProvenance = providerProvenance
        self.granularity = granularity
    }

    /// Stable identity for a source event. UUIDs would change on every refresh.
    var id: String {
        "\(source.rawValue):\(sessionId):\(timestamp.timeIntervalSince1970):\(model)"
    }

    var sessionKey: SessionKey {
        SessionKey(source: source, sessionId: sessionId)
    }

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
        case source
        case provider
        case providerRawValue
        case providerProvenance
        case granularity
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        model = try values.decode(String.self, forKey: .model)
        inputTokens = try values.decode(Int.self, forKey: .inputTokens)
        outputTokens = try values.decode(Int.self, forKey: .outputTokens)
        cacheCreationTokens = try values.decode(Int.self, forKey: .cacheCreationTokens)
        cacheReadTokens = try values.decode(Int.self, forKey: .cacheReadTokens)
        sessionId = try values.decode(String.self, forKey: .sessionId)
        projectPath = try values.decode(String.self, forKey: .projectPath)
        source = try values.decode(TokenSource.self, forKey: .source)
        provider = try values.decodeIfPresent(BillingProvider.self, forKey: .provider) ?? .unknown
        providerRawValue = try values.decodeIfPresent(String.self, forKey: .providerRawValue)
        providerProvenance = try values.decodeIfPresent(ProviderMetadataProvenance.self, forKey: .providerProvenance) ?? .unavailable
        granularity = try values.decodeIfPresent(TokenDataGranularity.self, forKey: .granularity) ?? .requestEvent
    }
}

struct ModelTokenUsage: Identifiable {
    let model: String
    let source: TokenSource
    let provider: BillingProvider
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

    /// Stable identity for charts and model-based navigation.
    var chartID: String {
        "\(source.rawValue):\(provider.rawValue):\(model)"
    }

    var id: String { chartID }
}

struct SessionTokenUsage: Identifiable {
    let sessionId: String
    let title: String?
    let projectPath: String
    let model: String
    let source: TokenSource
    let providers: [BillingProvider]
    let firstTimestamp: Date
    let lastTimestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let models: [ModelTokenUsage]

    var id: String { sessionKey.id }

    var sessionKey: SessionKey {
        SessionKey(source: source, sessionId: sessionId)
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var providerDisplayName: String {
        if providers.count > 1 { return "Multiple providers" }
        return providers.first?.displayName ?? BillingProvider.unknown.displayName
    }

    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return projectDisplayName
    }

    /// Last path component of the project, human-readable.
    ///
    /// `projectPath` arrives in one of two shapes depending on source:
    ///   - a real working-directory path (`/Users/foo/.../my-project`) from
    ///     the JSONL `cwd` / the SQLite `directory` column, or
    ///   - the dash-encoded folder name (`-Users-foo-...-my-project`) used as
    ///     a fallback when no `cwd` is present.
    /// A leading `/` distinguishes the two: real paths are used as-is so a
    /// hyphen-bearing directory such as `application-tracker` is preserved;
    /// encoded names have their dashes expanded to slashes first.
    var projectDisplayName: String {
        if projectPath.hasPrefix("/") {
            return (projectPath as NSString).lastPathComponent
        }
        let asPath = projectPath.replacingOccurrences(of: "-", with: "/")
        return (asPath as NSString).lastPathComponent
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
        let lower = model.lowercased()
        if lower.contains("opus") {
            if lower.contains("4-6") || lower.contains("4.6") {
                return "Opus 4.6"
            } else if lower.contains("4-5") || lower.contains("4.5") {
                return "Opus 4.5"
            }
            return "Opus"
        } else if lower.contains("sonnet") {
            if lower.contains("4-6") || lower.contains("4.6") {
                return "Sonnet 4.6"
            } else if lower.contains("4-5") || lower.contains("4.5") {
                return "Sonnet 4.5"
            } else if lower.contains("3-5") || lower.contains("3.5") {
                return "Sonnet 3.5"
            }
            return "Sonnet"
        } else if lower.contains("haiku") {
            if lower.contains("4-5") || lower.contains("4.5") {
                return "Haiku 4.5"
            } else if lower.contains("3-5") || lower.contains("3.5") {
                return "Haiku 3.5"
            }
            return "Haiku"
        } else if lower.contains("glm") {
            // ZCode models, e.g. "GLM-5.2", "glm-5.2
            if lower.contains("5.2") || lower.contains("5-2") {
                return "GLM 5.2"
            } else if lower.contains("4.5") || lower.contains("4-5") {
                return "GLM 4.5"
            } else if lower.contains("4") {
                return "GLM 4"
            }
            return lower
        }
        return model
    }

    static func color(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") {
            return "purple"
        } else if lower.contains("sonnet") {
            return "blue"
        } else if lower.contains("haiku") {
            return "orange"
        } else if lower.contains("glm") {
            return "teal"
        }
        return "gray"
    }
}

struct DailyTokenUsage: Identifiable {
    let date: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var id: Date { date }

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

/// Represents a `user` line in a session file. Used only to derive a
/// display title from the first human prompt when no `ai-title` exists.
struct UserPromptMessage: Codable {
    let type: String
    let message: Message?

    struct Message: Codable {
        /// `content` is either a plain string or an array of parts, each
        /// `{ "type": "text", "text": "..." }`. We decode to an untyped
        /// container so we can handle both shapes without a custom decoder.
        let content: Content?

        enum Content: Codable {
            case text(String)
            case parts([Part])

            struct Part: Codable {
                let type: String?
                let text: String?
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .text(string)
                } else if let parts = try? container.decode([Part].self) {
                    self = .parts(parts)
                } else {
                    self = .text("")
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }

            /// Plain text of this content, regardless of shape.
            var text: String {
                switch self {
                case .text(let string): return string
                case .parts(let parts):
                    return parts.compactMap { $0.text }.joined(separator: " ")
                }
            }
        }
    }
}
