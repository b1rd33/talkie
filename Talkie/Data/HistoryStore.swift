import Foundation
import SwiftData

/// Owns the SwiftData container for dictation history (spec §8).
@MainActor
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: DictationRecord.self, configurations: config)
    }

    func save(rawText: String, cleanedText: String, appBundleID: String?, appName: String?,
              duration: TimeInterval, engine: String, status: DictationStatus,
              cleanupModel: String? = nil, language: String? = nil) {
        let record = DictationRecord(rawText: rawText, cleanedText: cleanedText,
                                     appBundleID: appBundleID, appName: appName,
                                     durationSec: duration, engine: engine, status: status,
                                     cleanupModel: cleanupModel, language: language)
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
}
