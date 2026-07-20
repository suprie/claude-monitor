import Foundation

actor TokenParser: TokenUsageParser {
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

    /// Parses the `ai-title` line from each session file and returns a
    /// mapping of `sessionId` to its human-readable title.
    func parseSessionTitles() async -> [String: String] {
        var titles: [String: String] = [:]

        guard let jsonlFiles = findJSONLFiles() else {
            return titles
        }

        for file in jsonlFiles {
            for (sessionId, title) in await parseTitles(at: file) {
                titles[sessionId] = title
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

    /// Extracts the AI-generated title (if any) for the session stored in `url`.
    /// Falls back to the file name (without extension) as the sessionId if the
    /// `ai-title` line does not carry one.
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

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let titleMessage = try? decoder.decode(SessionTitleMessage.self, from: lineData),
                  titleMessage.type == "ai-title",
                  let title = titleMessage.aiTitle,
                  !title.isEmpty else {
                continue
            }
            let sessionId = titleMessage.sessionId ?? fallbackSessionId
            titles[sessionId] = title
        }

        return titles
    }
}
