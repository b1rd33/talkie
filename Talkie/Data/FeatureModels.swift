import Foundation
import SwiftData

@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var trigger: String
    @Attribute(.unique) var normalizedTrigger: String
    var expansion: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), trigger: String, normalizedTrigger: String,
         expansion: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.trigger = trigger
        self.normalizedTrigger = normalizedTrigger
        self.expansion = expansion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransformPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var instruction: String
    var shortcut: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, instruction: String,
         shortcut: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.shortcut = shortcut
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
