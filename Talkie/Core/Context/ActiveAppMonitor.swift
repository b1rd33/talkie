import AppKit

/// Frontmost-app context (spec §2 Context module). Bundle ID + name only —
/// Talkie never reads screen content. The coordinator keeps its Phase 2
/// closure seam; AppServices feeds it from here.
@MainActor
final class ActiveAppMonitor {
    var frontmost: (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
