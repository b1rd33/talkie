import CoreData
import Foundation
import SQLite3
import SwiftData

/// Owns the SwiftData container for dictation history (spec §8).
@MainActor
final class HistoryStore {
    let container: ModelContainer
    let storeURL: URL
    private var context: ModelContext { container.mainContext }

    convenience init(inMemory: Bool = false) throws {
        if inMemory {
            try self.init(
                storeURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("Talkie-in-memory.store"),
                inMemory: true)
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask)[0]
            try self.init(applicationSupportURL: applicationSupport)
        }
    }

    /// Production stores live in Talkie's own directory. SwiftData's unnamed
    /// default (`Application Support/default.store`) is process-global for
    /// non-sandboxed apps and can belong to an unrelated application.
    convenience init(applicationSupportURL: URL) throws {
        let fileManager = FileManager.default
        let directory = applicationSupportURL
            .appendingPathComponent("Talkie", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Talkie.store")
        let legacyURL = applicationSupportURL.appendingPathComponent("default.store")

        let migration: MigrationSnapshot?
        if !fileManager.fileExists(atPath: storeURL.path),
           Self.isGenuineLegacyTalkieStore(at: legacyURL) {
            migration = try Self.captureLegacyStore(at: legacyURL)
        } else {
            migration = nil
        }

        try self.init(storeURL: storeURL, inMemory: false)
        if let migration {
            try restore(migration)
        }
    }

    /// Explicit URL initializer used by migration tests and tooling.
    convenience init(storeURL: URL) throws {
        try self.init(storeURL: storeURL, inMemory: false)
    }

    private init(storeURL: URL, inMemory: Bool) throws {
        self.storeURL = storeURL
        let config = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration("Talkie", url: storeURL)
        container = try ModelContainer(for: DictationRecord.self, DictionaryEntry.self,
                                       AppStyleOverride.self, Snippet.self,
                                       TransformPreset.self, configurations: config)
    }

    /// A previous Talkie release may have used SwiftData's generic
    /// `default.store`. Metadata alone is not sufficient: Core Data can rewrite
    /// metadata before discovering that the entity tables belong to another app.
    /// Require both Talkie's model hash and its physical history table.
    private static func isGenuineLegacyTalkieStore(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator
                .metadataForPersistentStore(type: .sqlite, at: url),
              let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any],
              hashes["DictationRecord"] != nil else {
            return false
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return false
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let query = """
        SELECT 1 FROM sqlite_master
        WHERE type = 'table' AND name = 'ZDICTATIONRECORD'
        LIMIT 1
        """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private struct RecordSnapshot {
        let date: Date
        let rawText: String
        let cleanedText: String
        let appBundleID: String?
        let appName: String?
        let durationSec: Double
        let engine: String
        let status: DictationStatus
        let cleanupModel: String?
        let language: String?
        let detectedLanguages: [String]
        let audioPath: String?
        let deliveryOutcome: DeliveryOutcome?
        let audioHealthSummary: String?
    }

    private struct DictionarySnapshot {
        let term: String
        let soundsLike: String?
        let createdAt: Date
    }

    private struct StyleSnapshot {
        let bundleID: String
        let presetRaw: String
    }

    private struct SnippetSnapshot {
        let id: UUID
        let trigger: String
        let normalizedTrigger: String
        let expansion: String
        let createdAt: Date
        let updatedAt: Date
    }

    private struct TransformSnapshot {
        let id: UUID
        let name: String
        let instruction: String
        let shortcut: String?
        let createdAt: Date
        let updatedAt: Date
    }

    private struct MigrationSnapshot {
        let records: [RecordSnapshot]
        let dictionary: [DictionarySnapshot]
        let styles: [StyleSnapshot]
        let snippets: [SnippetSnapshot]
        let transforms: [TransformSnapshot]
    }

    private static func captureLegacyStore(at url: URL) throws -> MigrationSnapshot {
        let legacy = try HistoryStore(storeURL: url)
        let context = legacy.container.mainContext
        return try MigrationSnapshot(
            records: context.fetch(FetchDescriptor<DictationRecord>()).map {
                RecordSnapshot(
                    date: $0.date,
                    rawText: $0.rawText,
                    cleanedText: $0.cleanedText,
                    appBundleID: $0.appBundleID,
                    appName: $0.appName,
                    durationSec: $0.durationSec,
                    engine: $0.engine,
                    status: $0.status,
                    cleanupModel: $0.cleanupModel,
                    language: $0.language,
                    detectedLanguages: $0.detectedLanguages,
                    audioPath: $0.audioPath,
                    deliveryOutcome: Self.deliveryOutcome(from: $0),
                    audioHealthSummary: $0.audioHealthSummary)
            },
            dictionary: context.fetch(FetchDescriptor<DictionaryEntry>()).map {
                DictionarySnapshot(
                    term: $0.term,
                    soundsLike: $0.soundsLike,
                    createdAt: $0.createdAt)
            },
            styles: context.fetch(FetchDescriptor<AppStyleOverride>()).map {
                StyleSnapshot(bundleID: $0.bundleID, presetRaw: $0.presetRaw)
            },
            snippets: context.fetch(FetchDescriptor<Snippet>()).map {
                SnippetSnapshot(
                    id: $0.id,
                    trigger: $0.trigger,
                    normalizedTrigger: $0.normalizedTrigger,
                    expansion: $0.expansion,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt)
            },
            transforms: context.fetch(FetchDescriptor<TransformPreset>()).map {
                TransformSnapshot(
                    id: $0.id,
                    name: $0.name,
                    instruction: $0.instruction,
                    shortcut: $0.shortcut,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt)
            })
    }

    private func restore(_ snapshot: MigrationSnapshot) throws {
        for record in snapshot.records {
            context.insert(DictationRecord(
                date: record.date,
                rawText: record.rawText,
                cleanedText: record.cleanedText,
                appBundleID: record.appBundleID,
                appName: record.appName,
                durationSec: record.durationSec,
                engine: record.engine,
                status: record.status,
                cleanupModel: record.cleanupModel,
                language: record.language,
                detectedLanguages: record.detectedLanguages,
                audioPath: record.audioPath,
                deliveryOutcome: record.deliveryOutcome,
                audioHealthSummary: record.audioHealthSummary))
        }
        for entry in snapshot.dictionary {
            context.insert(DictionaryEntry(
                term: entry.term,
                soundsLike: entry.soundsLike,
                createdAt: entry.createdAt))
        }
        for style in snapshot.styles {
            let override = AppStyleOverride(
                bundleID: style.bundleID,
                preset: StylePreset(rawValue: style.presetRaw) ?? .neutral)
            override.presetRaw = style.presetRaw
            context.insert(override)
        }
        for snippet in snapshot.snippets {
            context.insert(Snippet(
                id: snippet.id,
                trigger: snippet.trigger,
                normalizedTrigger: snippet.normalizedTrigger,
                expansion: snippet.expansion,
                createdAt: snippet.createdAt,
                updatedAt: snippet.updatedAt))
        }
        for transform in snapshot.transforms {
            context.insert(TransformPreset(
                id: transform.id,
                name: transform.name,
                instruction: transform.instruction,
                shortcut: transform.shortcut,
                createdAt: transform.createdAt,
                updatedAt: transform.updatedAt))
        }
        try context.save()
    }

    func save(rawText: String, cleanedText: String, appBundleID: String?, appName: String?,
              duration: TimeInterval, engine: String, status: DictationStatus,
              cleanupModel: String? = nil, language: String? = nil,
              detectedLanguages: [String] = [], audioPath: String? = nil,
              deliveryOutcome: DeliveryOutcome? = nil,
              audioHealthSummary: String? = nil) {
        let record = DictationRecord(rawText: rawText, cleanedText: cleanedText,
                                     appBundleID: appBundleID, appName: appName,
                                     durationSec: duration, engine: engine, status: status,
                                     cleanupModel: cleanupModel, language: language,
                                     detectedLanguages: detectedLanguages,
                                     audioPath: audioPath,
                                     deliveryOutcome: deliveryOutcome,
                                     audioHealthSummary: audioHealthSummary)
        context.insert(record)
        try? context.save()
    }

    func recent(limit: Int) -> [DictationRecord] {
        var descriptor = FetchDescriptor<DictationRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func delete(_ record: DictationRecord) {
        context.delete(record)
        try? context.save()
    }

    // MARK: - Dictionary (spec §7/§8)

    func addTerm(_ term: String, soundsLike: String? = nil) throws {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let soundsLike = normalized(soundsLike)
        try DictionaryKeywordValidator.validate(trimmed)
        if let soundsLike { try DictionaryKeywordValidator.validate(soundsLike) }
        context.insert(DictionaryEntry(term: trimmed, soundsLike: soundsLike))
        try? context.save()
    }

    func updateTerm(_ entry: DictionaryEntry, term: String, soundsLike: String?) throws {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let soundsLike = normalized(soundsLike)
        try DictionaryKeywordValidator.validate(trimmed)
        if let soundsLike { try DictionaryKeywordValidator.validate(soundsLike) }
        entry.term = trimmed
        entry.soundsLike = soundsLike
        try? context.save()
    }

    func deleteTerm(_ entry: DictionaryEntry) {
        context.delete(entry)
        try? context.save()
    }

    func allTerms() -> [DictionaryEntry] {
        let descriptor = FetchDescriptor<DictionaryEntry>(sortBy: [SortDescriptor(\.term)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Exact spellings for ASR biasing and the cleanup prompt (spec §6).
    func dictionaryTermStrings() -> [String] {
        allTerms().map(\.term)
    }

    func dictionaryPromptTerms() -> [String] { allTerms().map(\.promptBias) }

    // MARK: - Snippets

    enum SnippetError: Error, Equatable {
        case emptyTrigger
        case emptyExpansion
        case duplicateTrigger
        case dictionaryConflict
    }

    func addSnippet(trigger: String, expansion: String) throws {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = SnippetProcessor.normalize(trimmedTrigger)
        guard !normalized.isEmpty else { throw SnippetError.emptyTrigger }
        guard !expansion.isEmpty else { throw SnippetError.emptyExpansion }
        guard !allSnippets().contains(where: { $0.normalizedTrigger == normalized }) else {
            throw SnippetError.duplicateTrigger
        }
        let correctionTriggers = allTerms().compactMap { $0.soundsLike }
            .map(SnippetProcessor.normalize)
        guard !correctionTriggers.contains(normalized) else {
            throw SnippetError.dictionaryConflict
        }
        context.insert(Snippet(trigger: trimmedTrigger, normalizedTrigger: normalized,
                               expansion: expansion))
        try context.save()
    }

    func allSnippets() -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.trigger)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func deleteSnippet(_ snippet: Snippet) {
        context.delete(snippet)
        try? context.save()
    }

    func snippetExpansions() -> [SnippetExpansion] {
        allSnippets().map { SnippetExpansion(trigger: $0.trigger, expansion: $0.expansion) }
    }

    // MARK: - Selection transform presets

    func addTransformPreset(name: String, instruction: String, shortcut: String? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instruction.isEmpty else { return }
        context.insert(TransformPreset(name: name, instruction: instruction, shortcut: shortcut))
        try? context.save()
    }

    func allTransformPresets() -> [TransformPreset] {
        let descriptor = FetchDescriptor<TransformPreset>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func deleteTransformPreset(_ preset: TransformPreset) {
        context.delete(preset)
        try? context.save()
    }

    private func normalized(_ soundsLike: String?) -> String? {
        guard let trimmed = soundsLike?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Style overrides (spec §6)

    func setStyleOverride(bundleID: String, preset: StylePreset) {
        if let existing = styleOverride(for: bundleID) {
            existing.presetRaw = preset.rawValue
        } else {
            context.insert(AppStyleOverride(bundleID: bundleID, preset: preset))
        }
        try? context.save()
    }

    func removeStyleOverride(bundleID: String) {
        guard let existing = styleOverride(for: bundleID) else { return }
        context.delete(existing)
        try? context.save()
    }

    func allStyleOverrides() -> [AppStyleOverride] {
        let descriptor = FetchDescriptor<AppStyleOverride>(sortBy: [SortDescriptor(\.bundleID)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// bundleID → presetRaw, the shape StyleResolver.overrides wants.
    func styleOverridesByBundleID() -> [String: String] {
        Dictionary(uniqueKeysWithValues: allStyleOverrides().map { ($0.bundleID, $0.presetRaw) })
    }

    private func styleOverride(for bundleID: String) -> AppStyleOverride? {
        var descriptor = FetchDescriptor<AppStyleOverride>(
            predicate: #Predicate { $0.bundleID == bundleID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Retry (spec §7/§10)

    /// A retried dictation succeeded: fill the texts in, flip to completed,
    /// and drop the kept-audio reference.
    func markRetried(_ record: DictationRecord, rawText: String, cleanedText: String,
                     deliveryOutcome: DeliveryOutcome? = nil,
                     audioHealthSummary: String? = nil) {
        record.rawText = rawText
        record.cleanedText = cleanedText
        record.statusRaw = DictationStatus.completed.rawValue
        record.wordCount = cleanedText.split { $0.isWhitespace }.count
        record.audioPath = nil
        record.deliveryRoute = deliveryOutcome?.route
        record.deliveryVerification = deliveryOutcome?.verification
        record.deliveryTargetBundleID = deliveryOutcome?.targetBundleID
        record.fallbackReason = deliveryOutcome?.fallbackReason
        record.revisionCount = deliveryOutcome?.revisionCount ?? 0
        record.audioHealthSummary = audioHealthSummary
        try? context.save()
    }

    private static func deliveryOutcome(from record: DictationRecord) -> DeliveryOutcome? {
        guard let route = record.deliveryRoute,
              let verification = record.deliveryVerification else { return nil }
        return DeliveryOutcome(
            route: route,
            verification: verification,
            targetBundleID: record.deliveryTargetBundleID,
            fallbackReason: record.fallbackReason,
            revisionCount: record.revisionCount)
    }

    // MARK: - Stats (spec §7 Home)

    struct Stats: Equatable {
        let totalWords: Int
        let totalDuration: TimeInterval
        let dictationsToday: Int
        let streakDays: Int
        // Spend estimates (PriceBook over completed records — retroactive, no migration)
        var costTotal: Double = 0
        var costThisMonth: Double = 0
        var costByEngine: [String: Double] = [:]
    }

    func stats(now: Date = Date(), calendar: Calendar = .current) -> Stats {
        let completedRaw = DictationStatus.completed.rawValue
        let completed = (try? context.fetch(FetchDescriptor<DictationRecord>(
            predicate: #Predicate { $0.statusRaw == completedRaw }))) ?? []
        let startOfDay = calendar.startOfDay(for: now)
        // spec §7 Home: consecutive calendar days ending today with ≥1 completed dictation.
        let activeDays = Set(completed.map { calendar.startOfDay(for: $0.date) })
        var streakDays = 0
        var cursor = startOfDay
        while activeDays.contains(cursor) {
            streakDays += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfDay
        var costTotal = 0.0
        var costThisMonth = 0.0
        var costByEngine: [String: Double] = [:]
        for record in completed {
            let cost = PriceBook.estimate(engine: record.engine, durationSec: record.durationSec,
                                          cleanupModel: record.cleanupModel, wordCount: record.wordCount)
            costTotal += cost
            if record.date >= monthStart { costThisMonth += cost }
            costByEngine[record.engine, default: 0] += cost
        }
        return Stats(
            totalWords: completed.reduce(0) { $0 + $1.wordCount },
            totalDuration: completed.reduce(0) { $0 + $1.durationSec },
            dictationsToday: completed.filter { $0.date >= startOfDay }.count,
            streakDays: streakDays,
            costTotal: costTotal,
            costThisMonth: costThisMonth,
            costByEngine: costByEngine)
    }
}
