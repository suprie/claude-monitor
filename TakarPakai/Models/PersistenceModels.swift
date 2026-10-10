import Foundation
import SwiftData

enum CacheSchema { static let currentVersion = 1 }

enum SourceReadStatus: String, Codable, Sendable { case succeeded, missing, failed }

struct SourceImportResult: Sendable {
    let source: TokenSource
    let status: SourceReadStatus
    let records: [TokenUsage]
    let titles: [SessionKey: String]
    let sourceIdentity: String?
    let completedAt: Date
    let errorDescription: String?

    static func succeeded(source: TokenSource, records: [TokenUsage], titles: [SessionKey: String], sourceIdentity: String? = nil, completedAt: Date = Date()) -> SourceImportResult {
        SourceImportResult(source: source, status: .succeeded, records: records, titles: titles, sourceIdentity: sourceIdentity, completedAt: completedAt, errorDescription: nil)
    }

    static func missing(source: TokenSource, completedAt: Date = Date()) -> SourceImportResult {
        SourceImportResult(source: source, status: .missing, records: [], titles: [:], sourceIdentity: nil, completedAt: completedAt, errorDescription: nil)
    }

    static func failed(source: TokenSource, error: Error, completedAt: Date = Date()) -> SourceImportResult {
        SourceImportResult(source: source, status: .failed, records: [], titles: [:], sourceIdentity: nil, completedAt: completedAt, errorDescription: error.localizedDescription)
    }
}

struct SourceSyncStatus: Sendable, Identifiable {
    let source: TokenSource
    let status: SourceReadStatus
    let lastSuccessfulRefresh: Date?
    let lastAttemptedRefresh: Date?
    let sourceIdentity: String?
    let errorDescription: String?
    var id: TokenSource { source }
}

@Model
final class CachedUsageRecord {
    @Attribute(.unique) var identity: String
    var timestamp: Date
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var sessionId: String
    var projectPath: String
    var sourceRawValue: String
    var providerRawValue: String
    var providerOriginalValue: String?
    var providerProvenanceRawValue: String
    var granularityRawValue: String

    init(record: TokenUsage) {
        identity = record.id; timestamp = record.timestamp; model = record.model
        inputTokens = record.inputTokens; outputTokens = record.outputTokens
        cacheCreationTokens = record.cacheCreationTokens; cacheReadTokens = record.cacheReadTokens
        sessionId = record.sessionId; projectPath = record.projectPath
        sourceRawValue = record.source.rawValue; providerRawValue = record.provider.rawValue
        providerOriginalValue = record.providerRawValue
        providerProvenanceRawValue = record.providerProvenance.rawValue
        granularityRawValue = record.granularity.rawValue
    }

    func update(from record: TokenUsage) {
        identity = record.id; timestamp = record.timestamp; model = record.model
        inputTokens = record.inputTokens; outputTokens = record.outputTokens
        cacheCreationTokens = record.cacheCreationTokens; cacheReadTokens = record.cacheReadTokens
        sessionId = record.sessionId; projectPath = record.projectPath
        sourceRawValue = record.source.rawValue; providerRawValue = record.provider.rawValue
        providerOriginalValue = record.providerRawValue
        providerProvenanceRawValue = record.providerProvenance.rawValue
        granularityRawValue = record.granularity.rawValue
    }

    var tokenUsage: TokenUsage? {
        guard let source = TokenSource(rawValue: sourceRawValue),
              let provenance = ProviderMetadataProvenance(rawValue: providerProvenanceRawValue),
              let granularity = TokenDataGranularity(rawValue: granularityRawValue) else { return nil }
        return TokenUsage(timestamp: timestamp, model: model, inputTokens: inputTokens, outputTokens: outputTokens,
                          cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens,
                          sessionId: sessionId, projectPath: projectPath, source: source,
                          provider: BillingProvider(rawValue: providerRawValue), providerRawValue: providerOriginalValue,
                          providerProvenance: provenance, granularity: granularity)
    }
}

@Model
final class CachedConversation {
    @Attribute(.unique) var identity: String
    var sourceRawValue: String
    var sessionId: String
    var title: String?
    var projectPath: String
    var lastActivity: Date

    init(key: SessionKey, title: String?, projectPath: String, lastActivity: Date) {
        identity = key.id; sourceRawValue = key.source.rawValue; sessionId = key.sessionId
        self.title = title; self.projectPath = projectPath; self.lastActivity = lastActivity
    }

    func update(title: String?, projectPath: String, lastActivity: Date) {
        self.title = title; self.projectPath = projectPath; self.lastActivity = lastActivity
    }
}

@Model
final class CachedSourceSyncState {
    @Attribute(.unique) var sourceRawValue: String
    var schemaVersion: Int
    var lastSuccessfulRefresh: Date?
    var lastAttemptedRefresh: Date?
    var sourceIdentity: String?
    var statusRawValue: String
    var errorDescription: String?

    init(source: TokenSource) {
        sourceRawValue = source.rawValue; schemaVersion = CacheSchema.currentVersion
        statusRawValue = SourceReadStatus.missing.rawValue
    }

    func apply(_ result: SourceImportResult) {
        schemaVersion = CacheSchema.currentVersion; lastAttemptedRefresh = result.completedAt
        if result.status == .succeeded { lastSuccessfulRefresh = result.completedAt; sourceIdentity = result.sourceIdentity }
        statusRawValue = result.status.rawValue; errorDescription = result.errorDescription
    }

    var snapshot: SourceSyncStatus? {
        guard let source = TokenSource(rawValue: sourceRawValue), let status = SourceReadStatus(rawValue: statusRawValue) else { return nil }
        return SourceSyncStatus(source: source, status: status, lastSuccessfulRefresh: lastSuccessfulRefresh,
                                lastAttemptedRefresh: lastAttemptedRefresh, sourceIdentity: sourceIdentity, errorDescription: errorDescription)
    }
}

enum TakarPakaiSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [CachedUsageRecord.self, CachedConversation.self, CachedSourceSyncState.self] }
}

enum TakarPakaiMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TakarPakaiSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
