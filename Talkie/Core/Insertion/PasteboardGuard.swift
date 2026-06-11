import AppKit

/// Snapshots the pasteboard, writes our transcript, and restores the user's
/// contents afterwards — unless someone else wrote in between (their copy wins).
@MainActor
final class PasteboardGuard {
    private struct Snapshot {
        let items: [[String: Data]]
        let changeCountAfterWrite: Int
    }

    private let pasteboard = NSPasteboard.general
    private var snapshot: Snapshot?

    func snapshotAndWrite(_ text: String) {
        let items: [[String: Data]] = pasteboard.pasteboardItems?.map { item in
            var byType: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { byType[type.rawValue] = data }
            }
            return byType
        } ?? []
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        snapshot = Snapshot(items: items, changeCountAfterWrite: pasteboard.changeCount)
    }

    func restoreIfUnchanged() {
        guard let snapshot else { return }
        self.snapshot = nil
        // If the changeCount moved past our write, the user copied something newer.
        guard pasteboard.changeCount == snapshot.changeCountAfterWrite else { return }
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let restored = snapshot.items.map { byType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (raw, data) in byType {
                item.setData(data, forType: NSPasteboard.PasteboardType(raw))
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
