import Foundation
import SwiftData

/// Personal dictionary term (spec §8): exact spelling + optional "sounds like" hint.
/// Terms feed ASR prompt biasing and the cleanup prompt; the hint is shown in the
/// Dictionary UI and ASR prompt biasing.
@Model
final class DictionaryEntry {
    var term: String
    var soundsLike: String?
    var createdAt: Date

    init(term: String, soundsLike: String? = nil, createdAt: Date = Date()) {
        self.term = term
        self.soundsLike = soundsLike
        self.createdAt = createdAt
    }

    var promptBias: String {
        guard let soundsLike, !soundsLike.isEmpty else { return term }
        return "\(term) (pronounced like \(soundsLike))"
    }
}
