import SwiftData
import SwiftUI

/// Personal dictionary (spec §7): exact spellings + optional "sounds like" hints.
/// Terms feed ASR prompt biasing and the cleanup prompt (wired in Task 10).
struct DictionaryView: View {
    let history: HistoryStore
    @Query(sort: \DictionaryEntry.term) private var entries: [DictionaryEntry]
    @State private var newTerm = ""
    @State private var newSoundsLike = ""
    @State private var editing: DictionaryEntry?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add a term") {
                    TextField("Exact spelling (e.g. Archiev)", text: $newTerm)
                    TextField("Sounds like (optional, e.g. ar-keev)", text: $newSoundsLike)
                    Button("Add") { add() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 190)

            List {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                            if let soundsLike = entry.soundsLike {
                                Text("sounds like “\(soundsLike)”")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { editing = entry } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Edit")
                        Button(role: .destructive) { history.deleteTerm(entry) }
                            label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete")
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No terms yet", systemImage: "character.book.closed",
                                           description: Text("Add names and jargon Talkie should always spell right."))
                }
            }
        }
        .navigationTitle("Dictionary")
        .sheet(item: $editing) { entry in
            DictionaryEditSheet(history: history, entry: entry)
        }
    }

    private func add() {
        history.addTerm(newTerm, soundsLike: newSoundsLike)
        newTerm = ""
        newSoundsLike = ""
    }
}

private struct DictionaryEditSheet: View {
    let history: HistoryStore
    let entry: DictionaryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var soundsLike = ""

    var body: some View {
        Form {
            TextField("Exact spelling", text: $term)
            TextField("Sounds like (optional)", text: $soundsLike)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    history.updateTerm(entry, term: term, soundsLike: soundsLike)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            term = entry.term
            soundsLike = entry.soundsLike ?? ""
        }
    }
}
