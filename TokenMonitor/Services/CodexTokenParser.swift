import Foundation

/// Reads Codex CLI token usage from the JSONL rollout files it writes at
/// `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<timestamp>-<uuid>.jsonl`.
///
/// Each file is a stream of typed lines: `session_meta` (once, carries
/// `sessionId`/`cwd`), `turn_context` (model in effect for upcoming turns),
/// and `event_msg` lines whose payload type `token_count` carries the
/// per-turn token delta. This parser mirrors `TokenParser`'s JSONL scan.
actor CodexTokenParser: TokenUsageParser {
    let source: TokenSource = .codex
    private let sessionsPath: String
    private let dateFormatter: ISO8601DateFormatter

    init(sessionsPath: String = NSHomeDirectory() + "/.codex/sessions") {
        self.sessionsPath = sessionsPath
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func parseAllTokenUsage() async -> [TokenUsage] {
        guard let jsonlFiles = findJSONLFiles() else {
            return []
        }

        var allUsage: [TokenUsage] = []
        for file in jsonlFiles {
            allUsage.append(contentsOf: parseFile(at: file))
        }
        return allUsage
    }

    func parseSource() async -> SourceImportResult {
        guard FileManager.default.fileExists(atPath: sessionsPath) else { return .missing(source: source) }
        return .succeeded(source: source, records: await parseAllTokenUsage(), titles: [:], sourceIdentity: sessionsPath)
    }

    private func findJSONLFiles() -> [URL]? {
        let fileManager = FileManager.default
        let sessionsURL = URL(fileURLWithPath: sessionsPath)

        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var jsonlFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
        return jsonlFiles
    }

    private func parseFile(at url: URL) -> [TokenUsage] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var projectPath = ""
        var currentModel = "unknown"
        var usages: [TokenUsage] = []

        let decoder = JSONDecoder()

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(CodexRolloutLine.self, from: lineData) else {
                continue
            }

            switch entry.type {
            case "session_meta":
                if let id = entry.payload?.id { sessionId = id }
                if let cwd = entry.payload?.cwd { projectPath = cwd }

            case "turn_context":
                if let model = entry.payload?.model { currentModel = model }

            case "event_msg":
                guard entry.payload?.type == "token_count",
                      let usage = entry.payload?.info?.last_token_usage,
                      let timestamp = parseTimestamp(entry.timestamp) else {
                    continue
                }
                usages.append(TokenUsage(
                    timestamp: timestamp,
                    model: currentModel,
                    inputTokens: usage.input_tokens ?? 0,
                    outputTokens: (usage.output_tokens ?? 0) + (usage.reasoning_output_tokens ?? 0),
                    cacheCreationTokens: 0,
                    cacheReadTokens: usage.cached_input_tokens ?? 0,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    source: .codex
                ))

            default:
                continue
            }
        }

        return usages
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = dateFormatter.date(from: raw) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}

/// One line of a Codex rollout JSONL file. Fields are optional/untyped
/// across the union of `session_meta` / `turn_context` / `event_msg` shapes;
/// only the fields relevant to token usage are decoded.
private struct CodexRolloutLine: Codable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Codable {
        // session_meta
        let id: String?
        let cwd: String?
        // turn_context
        let model: String?
        // event_msg
        let type: String?
        let info: Info?
    }

    struct Info: Codable {
        let last_token_usage: TokenCount?
    }

    struct TokenCount: Codable {
        let input_tokens: Int?
        let cached_input_tokens: Int?
        let output_tokens: Int?
        let reasoning_output_tokens: Int?
    }
}
