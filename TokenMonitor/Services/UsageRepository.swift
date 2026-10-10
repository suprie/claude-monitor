import Foundation
import SwiftData

struct CachedStoreSnapshot: Sendable {
    let snapshot: UsageSnapshot
    let sourceStatuses: [SourceSyncStatus]
}

/// Owns the app's derived SwiftData cache. Every write uses a fresh context so
/// a failed source import cannot publish a partially saved source snapshot.
actor UsageRepository {
    private let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: TokenMonitorSchemaV1.self)
        let configuration = ModelConfiguration("TokenMonitorCache", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, migrationPlan: TokenMonitorMigrationPlan.self, configurations: configuration)
    }

    func load() throws -> CachedStoreSnapshot {
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<CachedUsageRecord>()).compactMap(\.tokenUsage)
        let conversations = try context.fetch(FetchDescriptor<CachedConversation>())
        let titlePairs: [(SessionKey, String)] = conversations.compactMap { conversation in
            guard let source = TokenSource(rawValue: conversation.sourceRawValue), let title = conversation.title, !title.isEmpty else { return nil }
            return (SessionKey(source: source, sessionId: conversation.sessionId), title)
        }
        let titles: [SessionKey: String] = Dictionary(uniqueKeysWithValues: titlePairs)
        let states = try context.fetch(FetchDescriptor<CachedSourceSyncState>()).compactMap(\.snapshot)
        let latestRefresh = states.compactMap(\.lastSuccessfulRefresh).max()
        return CachedStoreSnapshot(snapshot: UsageSnapshot(records: records, titles: titles, createdAt: latestRefresh ?? Date(), lastSuccessfulRefresh: latestRefresh),
                                   sourceStatuses: states.sorted { $0.source.rawValue < $1.source.rawValue })
    }

    func importSource(_ result: SourceImportResult) throws {
        let context = ModelContext(container)
        let existingRecords = try context.fetch(FetchDescriptor<CachedUsageRecord>())
        let sourceRecords = existingRecords.filter { $0.sourceRawValue == result.source.rawValue }
        if result.status == .succeeded {
            let incomingIDs = Set(result.records.map(\.id))
            for record in sourceRecords where !incomingIDs.contains(record.identity) { context.delete(record) }
            let recordsByID = Dictionary(uniqueKeysWithValues: sourceRecords.map { ($0.identity, $0) })
            for record in result.records {
                if let cached = recordsByID[record.id] { cached.update(from: record) }
                else { context.insert(CachedUsageRecord(record: record)) }
            }

            let conversationRecords = Dictionary(grouping: result.records, by: \.sessionKey)
            let existingConversations = try context.fetch(FetchDescriptor<CachedConversation>())
            let conversationsByID = Dictionary(uniqueKeysWithValues: existingConversations.map { ($0.identity, $0) })
            let incomingConversationIDs = Set(conversationRecords.keys.map(\.id))
            for conversation in existingConversations
            where conversation.sourceRawValue == result.source.rawValue && !incomingConversationIDs.contains(conversation.identity) {
                context.delete(conversation)
            }
            for (key, records) in conversationRecords {
                guard let latest = records.max(by: { $0.timestamp < $1.timestamp }) else { continue }
                if let conversation = conversationsByID[key.id] {
                    conversation.update(title: result.titles[key], projectPath: latest.projectPath, lastActivity: latest.timestamp)
                } else {
                    context.insert(CachedConversation(key: key, title: result.titles[key], projectPath: latest.projectPath, lastActivity: latest.timestamp))
                }
            }
        }

        let states = try context.fetch(FetchDescriptor<CachedSourceSyncState>())
        if let state = states.first(where: { $0.sourceRawValue == result.source.rawValue }) { state.apply(result) }
        else { let state = CachedSourceSyncState(source: result.source); state.apply(result); context.insert(state) }
        try context.save()
    }

    /// Clears only Token Monitor's derived cache. Source files, databases, and
    /// any future pricing overrides live outside this container and are never touched.
    func rebuildCache() throws {
        let context = ModelContext(container)
        try context.fetch(FetchDescriptor<CachedUsageRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CachedConversation>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CachedSourceSyncState>()).forEach(context.delete)
        try context.save()
    }
}
