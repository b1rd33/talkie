import Foundation
import SwiftData

/// Owns the SwiftData container for dictation history (spec §8).
@MainActor
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: DictationRecord.self, DictionaryEntry.self,
                                       AppStyleOverride.self, configurations: config)
    }

    func save(rawText: String, cleanedText: String, appBundleID: String?, appName: String?,
              duration: TimeInterval, engine: String, status: DictationStatus,
              cleanupModel: String? = nil, language: String? = nil, audioPath: String? = nil) {
        let record = DictationRecord(rawText: rawText, cleanedText: cleanedText,
                                     appBundleID: appBundleID, appName: appName,
                                     durationSec: duration, engine: engine, status: status,
                                     cleanupModel: cleanupModel, language: language,
                                     audioPath: audioPath)
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

    func addTerm(_ term: String, soundsLike: String? = nil) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(DictionaryEntry(term: trimmed, soundsLike: normalized(soundsLike)))
        try? context.save()
    }

    func updateTerm(_ entry: DictionaryEntry, term: String, soundsLike: String?) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entry.term = trimmed
        entry.soundsLike = normalized(soundsLike)
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
    func markRetried(_ record: DictationRecord, rawText: String, cleanedText: String) {
        record.rawText = rawText
        record.cleanedText = cleanedText
        record.statusRaw = DictationStatus.completed.rawValue
        record.wordCount = cleanedText.split { $0.isWhitespace }.count
        record.audioPath = nil
        try? context.save()
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
