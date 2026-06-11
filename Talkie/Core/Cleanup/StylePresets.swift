import Foundation

/// How aggressively cleanup rewrites the transcript (spec §6).
/// `.none` means the coordinator skips the LLM entirely and inserts raw ASR text.
enum CleanupLevel: String, CaseIterable, Sendable {
    case none, light, medium, high
}

/// App-aware tone preset, keyed by the frontmost app's bundle ID (spec §6).
enum StylePreset: String, CaseIterable, Sendable {
    case casual, polished, technical, neutral
}

/// Resolves the style preset for a target app: user overrides win, then the
/// built-in table, then `.neutral`. Pure logic — overrides are injected as a
/// closure (production feeds it from AppStyleOverride records, Task 10).
struct StyleResolver {
    /// bundleID → StylePreset rawValue.
    var overrides: () -> [String: String] = { [:] }

    static let builtIn: [String: StylePreset] = [
        // chat → casual
        "com.tinyspeck.slackmacgap": .casual,        // Slack
        "com.hnc.Discord": .casual,                  // Discord
        "com.apple.MobileSMS": .casual,              // Messages
        "net.whatsapp.WhatsApp": .casual,            // WhatsApp
        "ru.keepcoder.Telegram": .casual,            // Telegram (App Store)
        "org.telegram.desktop": .casual,             // Telegram Desktop
        // email → polished
        "com.apple.mail": .polished,                 // Mail
        "com.microsoft.Outlook": .polished,          // Outlook
        "com.readdle.SparkDesktop": .polished,       // Spark Desktop
        "com.readdle.smartemail-Mac": .polished,     // Spark (classic)
        // code & terminals → technical
        "com.apple.dt.Xcode": .technical,            // Xcode
        "com.todesktop.230313mzl4w4u92": .technical, // Cursor
        "com.microsoft.VSCode": .technical,          // VS Code
        "com.apple.Terminal": .technical,            // Terminal
        "com.googlecode.iterm2": .technical,         // iTerm2
        "dev.warp.Warp-Stable": .technical,          // Warp
        "com.mitchellh.ghostty": .technical,         // Ghostty
    ]

    func resolve(bundleID: String?) -> StylePreset {
        guard let bundleID else { return .neutral }
        if let raw = overrides()[bundleID], let preset = StylePreset(rawValue: raw) {
            return preset
        }
        return Self.builtIn[bundleID] ?? .neutral
    }
}
