import Foundation
import SwiftData

/// Per-app style override (spec §6/§8): the user pins a preset for a bundle ID.
/// Joins HistoryStore's ModelContainer schema in Task 5.
@Model
final class AppStyleOverride {
    @Attribute(.unique) var bundleID: String
    var presetRaw: String

    var preset: StylePreset { StylePreset(rawValue: presetRaw) ?? .neutral }

    init(bundleID: String, preset: StylePreset) {
        self.bundleID = bundleID
        self.presetRaw = preset.rawValue
    }
}
