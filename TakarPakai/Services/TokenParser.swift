import Foundation

actor TokenParser: TokenUsageParser {
    let source: TokenSource = .claude
    private let projectsPath: String
    private let dateFormatter: ISO8601DateFormatter

    init() {
        self.projectsPath = NSHomeDirectory() + "/.claude/projects"
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func parseAllTokenUsage() async -> [TokenUsage] {
        var allUsage: [TokenUsage] = []

        guard let jsonlFiles = findJSONLFiles() else {
            return allUsage
        }

        for file in jsonlFiles {
            let usages = await parseFile(at: file)
            allUsage.append(contentsOf: usages)
        }

        return allUsage
    }

    func parseSource() async -> SourceImportResult {
        guard FileManager.default.fileExists(atPath: projectsPath) else { return .missing(source: source) }
        return .succeeded(source: source, records: await parseAllTokenUsage(), titles: await parseSessionTitles(), sourceIdentity: projectsPath)
    }

    /// Parses the `ai-title` line from each session file and returns a
    /// mapping of `sessionId` to its human-readable title.
    ///
    /// Recent Claude sessions no longer emit an `ai-title` line. As a
    /// fallback, when no explicit title is found we derive one from the
    /// first useful human prompt in the session. The explicit title always
    /// wins when present.
    func parseSessionTitles() async -> [SessionKey: String] {
        var titles: [SessionKey: String] = [:]

        guard let jsonlFiles = findJSONLFiles() else {
            return titles
        }

        for file in jsonlFiles {
            for (sessionId, title) in await parseTitles(at: file) {
                titles[SessionKey(source: .claude, sessionId: sessionId)] = title
            }
        }
        return titles
    }

    private func findJSONLFiles() -> [URL]? {
        let fileManager = FileManager.default
        let projectsURL = URL(fileURLWithPath: projectsPath)

        guard let enumerator = fileManager.enumerator(
            at: projectsURL,
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

    private func parseFile(at url: URL) async -> [TokenUsage] {
        var usages: [TokenUsage] = []

        guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
            return usages
        }

        defer { try? fileHandle.close() }

        guard let data = try? fileHandle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return usages
        }

        // Derive a default project path from the parent directory name
        // (e.g. "-Users-foo-bar-project" -> "-Users-foo-bar-project").
        // Prefer the `cwd` field on each assistant line when available.
        let projectDirName = url.deletingLastPathComponent().lastPathComponent
        let sessionIdFromFile = url.deletingPathExtension().lastPathComponent

        let lines = content.components(separatedBy: .newlines)
        let decoder = JSONDecoder()

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let message = try decoder.decode(AssistantMessage.self, from: lineData)

                guard message.type == "assistant",
                      let timestampStr = message.timestamp,
                      let messageContent = message.message,
                      let usage = messageContent.usage else {
                    continue
                }

                // Try parsing with fractional seconds first, then without
                var date: Date?
                date = dateFormatter.date(from: timestampStr)

                if date == nil {
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    date = fallbackFormatter.date(from: timestampStr)
                }

                guard let timestamp = date else { continue }

                let model = messageContent.model ?? "unknown"
                // Prefer the cwd on the assistant line over the directory name,
                // since it is the actual working directory the session ran in.
                let projectPath = message.cwd ?? projectDirName
                let sessionId = message.sessionId ?? sessionIdFromFile

                let tokenUsage = TokenUsage(
                    timestamp: timestamp,
                    model: model,
                    inputTokens: usage.input_tokens ?? 0,
                    outputTokens: usage.output_tokens ?? 0,
                    cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
                    cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    source: .claude
                )

                usages.append(tokenUsage)
            } catch {
                // Skip malformed lines
                continue
            }
        }

        return usages
    }

    /// Extracts a title for the session stored in `url`.
    ///
    /// Prefers the AI-generated `ai-title` line. When none is present — which
    /// is the case for recent Claude sessions — derives a title from the first
    /// useful human prompt in the file. Falls back to the file name (without
    /// extension) as the sessionId when a line does not carry one.
    private func parseTitles(at url: URL) async -> [String: String] {
        var titles: [String: String] = [:]

        guard let fileHandle = FileHandle(forReadingAtPath: url.path),
              let data = try? fileHandle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return titles
        }
        try? fileHandle.close()

        let fallbackSessionId = url.deletingPathExtension().lastPathComponent
        let decoder = JSONDecoder()
        let lines = content.components(separatedBy: .newlines)

        var resolvedSessionId = fallbackSessionId
        var firstPromptTitle: String?

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            // Explicit AI title wins; once we have it, no need to keep scanning.
            if let titleMessage = try? decoder.decode(SessionTitleMessage.self, from: lineData),
               titleMessage.type == "ai-title",
               let title = titleMessage.aiTitle,
               !title.isEmpty {
                let sessionId = titleMessage.sessionId ?? fallbackSessionId
                resolvedSessionId = sessionId
                titles[sessionId] = title
                continue
            }

            // Capture the first useful prompt as a fallback. Only set once
            // per file so we keep the very first user turn.
            if firstPromptTitle == nil,
               let userMessage = try? decoder.decode(UserPromptMessage.self, from: lineData),
               userMessage.type == "user" {
                // Track the authoritative sessionId from the first line that
                // carries one, so the prompt-derived title is keyed correctly.
                if let candidate = try? decoder.decode(AssistantMessage.self, from: lineData),
                   let sessionId = candidate.sessionId {
                    resolvedSessionId = sessionId
                }
                if let promptTitle = Self.title(fromPrompt: userMessage.message?.content?.text) {
                    firstPromptTitle = promptTitle
                }
            }
        }

        // No explicit title — fall back to the first prompt if we found one.
        if titles[resolvedSessionId] == nil, let promptTitle = firstPromptTitle {
            titles[resolvedSessionId] = promptTitle
        }

        return titles
    }

    /// Reduces a raw user prompt to a short, human-readable title.
    /// Returns nil when the prompt is a system preamble, an interruption
    /// notice, or otherwise unsuitable to use as a label.
    private static func title(fromPrompt text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        // Strip any leading skill/command preamble that the harness injects,
        // e.g. "Base directory for this skill: ...", so the first real turn
        // is what surfaces in the UI.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Skip boilerplate that isn't a meaningful description of the work.
        let boilerplate = [
            "<local-command", "<command-message", "<task-notification",
            "[Request interrupted"
        ]
        if boilerplate.contains(where: { trimmed.hasPrefix($0) }) {
            return nil
        }

        // Collapse whitespace and truncate for a compact menu label.
        let collapsed = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        return collapsed
    }
}
