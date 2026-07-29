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
    var detectedLanguagesJSON: String?
    /// Failed/cancelled dictations keep their audio here for retry (spec §8/§10).
    var audioPath: String?
    var statusRaw: String
    var wordCount: Int

    var status: DictationStatus { DictationStatus(rawValue: statusRaw) ?? .completed }
    var detectedLanguages: [String] {
        get {
            guard let data = detectedLanguagesJSON?.data(using: .utf8) else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            detectedLanguagesJSON = (try? JSONEncoder().encode(newValue))
                .map { String(decoding: $0, as: UTF8.self) }
        }
    }

    init(date: Date = Date(), rawText: String, cleanedText: String,
         appBundleID: String?, appName: String?, durationSec: Double,
         engine: String, status: DictationStatus,
         cleanupModel: String? = nil, language: String? = nil,
         detectedLanguages: [String] = [],
         audioPath: String? = nil) {
        self.date = date
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.appBundleID = appBundleID
        self.appName = appName
        self.durationSec = durationSec
        self.engine = engine
        self.cleanupModel = cleanupModel
        self.language = language
        self.detectedLanguagesJSON = (try? JSONEncoder().encode(detectedLanguages))
            .map { String(decoding: $0, as: UTF8.self) }
        self.audioPath = audioPath
        self.statusRaw = status.rawValue
        self.wordCount = cleanedText.split { $0.isWhitespace }.count
    }
}
