import Foundation

enum PillStyle: String, CaseIterable, Sendable {
    case bareWaveform
    case thinkingOrb
    case dynamicIsland
    case liquidGlass
    case hidden

    static let `default` = PillStyle.bareWaveform

    init(migrating raw: String?) {
        switch raw {
        case "inkLine", "calmFlowRibbon", "bareWave": self = .thinkingOrb
        case "frostedGlass": self = .liquidGlass
        default: self = raw.flatMap(Self.init(rawValue:)) ?? .default
        }
    }
}
