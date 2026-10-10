import Foundation

/// A source of token-usage records (Claude JSONL, ZCode SQLite, Hermes SQLite, …).
///
/// Concrete parsers are `actor`s, so the protocol is `Sendable` and instances
/// can be stored on the `@MainActor`-isolated `TokenService` and fanned out
/// across a `TaskGroup`.
protocol TokenUsageParser: Sendable {
    /// The recording application represented by this parser.
    var source: TokenSource { get }

    /// All token-usage records this source can produce.
    func parseAllTokenUsage() async -> [TokenUsage]

    /// Mapping of source-qualified session identity → human-readable title, for sources that store
    /// titles out-of-band from the usage rows. Sources without titles return `[:]`.
    func parseSessionTitles() async -> [SessionKey: String]

    /// Reads one complete source snapshot and distinguishes an absent source
    /// from a successful empty read.
    func parseSource() async -> SourceImportResult
}

/// Default "no titles" implementation — used by the SQLite-backed parsers,
/// which already embed the working directory in each usage row.
extension TokenUsageParser {
    var source: TokenSource { .claude }

    func parseSessionTitles() async -> [SessionKey: String] {
        [:]
    }

    func parseSource() async -> SourceImportResult {
        SourceImportResult.succeeded(source: source, records: await parseAllTokenUsage(), titles: await parseSessionTitles())
    }
}
