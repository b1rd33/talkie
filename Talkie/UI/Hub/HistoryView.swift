import AppKit
import SwiftData
import SwiftUI

/// Searchable dictation history (spec §7): cleaned text, expandable raw text,
/// source app icon, copy cleaned/raw, delete, retry on failed/cancelled rows,
/// status badges.
struct HistoryView: View {
    let history: HistoryStore
    @State private var searchText = ""

    var body: some View {
        HistoryListView(history: history, searchText: searchText)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search dictations")
            .navigationTitle("History")
    }
}

/// Separate child view: @Query predicates are set in init, so the search text
/// must arrive as a plain value to rebuild the query when it changes.
private struct HistoryListView: View {
    let history: HistoryStore
    @Query private var records: [DictationRecord]
    @State private var expandedIDs: Set<PersistentIdentifier> = []

    init(history: HistoryStore, searchText: String) {
        self.history = history
        if searchText.isEmpty {
            _records = Query(sort: \DictationRecord.date, order: .reverse)
        } else {
            _records = Query(filter: #Predicate<DictationRecord> {
                $0.cleanedText.localizedStandardContains(searchText)
                    || $0.rawText.localizedStandardContains(searchText)
            }, sort: \DictationRecord.date, order: .reverse)
        }
    }

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView("No dictations", systemImage: "waveform",
                                   description: Text("Hold fn and speak — every dictation lands here."))
        } else {
            List {
                ForEach(records) { record in
                    row(record)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func row(_ record: DictationRecord) -> some View {
        let expanded = expandedIDs.contains(record.persistentModelID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(record.cleanedText.isEmpty ? "(no text)" : record.cleanedText)
                    .lineLimit(expanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusBadge(record.status)
            }
            HStack(spacing: 8) {
                appIcon(record.appBundleID)
                    .resizable()
                    .frame(width: 16, height: 16) // spec §7: source app icon
                Text(record.appName ?? "Unknown app")
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                Text("\(Int(record.durationSec))s · \(record.engine)")
                Spacer()
                if record.status != .completed, record.audioPath != nil {
                    Button { // spec §7: failed/cancelled rows offer retry (audio kept in Task 5)
                        Task {
                            if let text = await AppServices.shared.coordinator.retry(record) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Retry from kept audio — copies the result")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.cleanedText, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy cleaned text")
                Button { // spec §7: re-copy raw
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.rawText, forType: .string)
                } label: { Image(systemName: "doc.on.doc.fill") }
                .buttonStyle(.borderless)
                .help("Copy raw transcript")
                .disabled(record.rawText.isEmpty)
                Button(role: .destructive) {
                    expandedIDs.remove(record.persistentModelID)
                    history.delete(record)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if expanded, !record.rawText.isEmpty {
                Text(record.rawText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { toggle(record) }
    }

    private func toggle(_ record: DictationRecord) {
        if expandedIDs.contains(record.persistentModelID) {
            expandedIDs.remove(record.persistentModelID)
        } else {
            expandedIDs.insert(record.persistentModelID)
        }
    }

    /// Source app icon (spec §7), resolved from the stored bundle ID.
    private func appIcon(_ bundleID: String?) -> Image {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app")
    }

    private func statusBadge(_ status: DictationStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: DictationStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}
