import Foundation

actor TokenParser {
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

                let tokenUsage = TokenUsage(
                    timestamp: timestamp,
                    model: model,
                    inputTokens: usage.input_tokens ?? 0,
                    outputTokens: usage.output_tokens ?? 0,
                    cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
                    cacheReadTokens: usage.cache_read_input_tokens ?? 0
                )

                usages.append(tokenUsage)
            } catch {
                // Skip malformed lines
                continue
            }
        }

        return usages
    }
}
