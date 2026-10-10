import Foundation

/// Reads DeepSeek Harness's persisted session aggregates from
/// `~/.dsh/storages/session_projcache/sessions`.
///
/// Harness keeps the fast-to-read aggregate in one JSON file per session. The
/// aggregate contains uncached input, output, and cache token totals, but not
/// a model or per-request timestamp. Those fields are represented explicitly
/// as source-configuration metadata and lifetime aggregates. The compressed
/// `session.v4.jsonl.zstd` stream is intentionally not read here; it can be
/// added later when request-level/day-level DeepSeek charts are needed.
actor DeepSeekHarnessTokenParser: TokenUsageParser {
    let source: TokenSource = .deepseekHarness

    private let sessionsPath: String
    private let model: String
    private let providerRawValue: String

    init(
        sessionsPath: String = NSHomeDirectory() + "/.dsh/storages/session_projcache/sessions",
        model: String = "deepseek-flash",
        providerRawValue: String = "deepseek-account"
    ) {
        self.sessionsPath = sessionsPath
        self.model = model
        self.providerRawValue = providerRawValue
    }

    func parseAllTokenUsage() async -> [TokenUsage] {
        guard let files = jsonFiles() else { return [] }
        return files.compactMap(parseFile(at:))
    }

    func parseSessionTitles() async -> [SessionKey: String] {
        guard let files = jsonFiles() else { return [:] }
        return files.reduce(into: [:]) { titles, url in
            guard let session = decodeSession(at: url),
                  let title = session.record.rows.title?.value,
                  !title.isEmpty else { return }
            titles[SessionKey(source: source, sessionId: sessionID(for: url))] = title
        }
    }

    func parseSource() async -> SourceImportResult {
        guard FileManager.default.fileExists(atPath: sessionsPath) else {
            return .missing(source: source)
        }

        return .succeeded(
            source: source,
            records: await parseAllTokenUsage(),
            titles: await parseSessionTitles(),
            sourceIdentity: sessionsPath
        )
    }

    private func jsonFiles() -> [URL]? {
        let directory = URL(fileURLWithPath: sessionsPath, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return names
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func parseFile(at url: URL) -> TokenUsage? {
        guard let session = decodeSession(at: url),
              let totals = session.record.rows.tokenUsage?.value.totals else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(session.record.identity.createdAt) / 1000)

        return TokenUsage(
            timestamp: timestamp,
            model: model,
            inputTokens: totals.uncachedInputTokens,
            outputTokens: totals.outputTokens,
            cacheCreationTokens: totals.cacheWriteTokens,
            cacheReadTokens: totals.cacheReadTokens,
            sessionId: sessionID(for: url),
            projectPath: session.record.identity.cwd,
            source: source,
            provider: BillingProvider(rawValue: providerRawValue),
            providerRawValue: providerRawValue,
            providerProvenance: .sourceConfiguration,
            granularity: .lifetimeSessionModelAggregate
        )
    }

    private func decodeSession(at url: URL) -> HarnessSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HarnessSession.self, from: data)
    }

    private func sessionID(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

private struct HarnessSession: Decodable {
    let record: Record

    struct Record: Decodable {
        let identity: Identity
        let rows: Rows
    }

    struct Identity: Decodable {
        let createdAt: Int64
        let cwd: String
    }

    struct Rows: Decodable {
        let title: Versioned<String>?
        let tokenUsage: Versioned<TokenUsageValue>?
    }

    struct Versioned<Value: Decodable>: Decodable {
        let value: Value

        enum CodingKeys: String, CodingKey { case value = "val" }
    }

    struct TokenUsageValue: Decodable {
        let totals: Totals
    }

    struct Totals: Decodable {
        let uncachedInputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
    }
}
