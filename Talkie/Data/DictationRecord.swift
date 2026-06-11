import Foundation
import SwiftData

enum DictationStatus: String, Codable {
    case completed, failed, cancelled
}

@Model
final class DictationRecord {
    var date: Date
    var rawText: String
    var cleanedText: String
    var appBundleID: String?
    var appName: String?
    var durationSec: Double
    var engine: String
    // Spec §8 schema — kept in the v1 schema so no migration is needed later;
    // populated by Phase 4's cleanup-levels and language-pin work, nil until then.
    var cleanupModel: String?
    var language: String?
    var statusRaw: String
    var wordCount: Int

    var status: DictationStatus { DictationStatus(rawValue: statusRaw) ?? .completed }

    init(date: Date = Date(), rawText: String, cleanedText: String,
         appBundleID: String?, appName: String?, durationSec: Double,
         engine: String, status: DictationStatus,
         cleanupModel: String? = nil, language: String? = nil) {
        self.date = date
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.appBundleID = appBundleID
        self.appName = appName
        self.durationSec = durationSec
        self.engine = engine
        self.cleanupModel = cleanupModel
        self.language = language
        self.statusRaw = status.rawValue
        self.wordCount = cleanedText.split { $0.isWhitespace }.count
    }
}
