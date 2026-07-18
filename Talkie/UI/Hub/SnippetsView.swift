import SwiftData
import SwiftUI

struct SnippetsView: View {
    let history: HistoryStore
    @Query(sort: \Snippet.trigger) private var snippets: [Snippet]
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add a voice snippet") {
                    TextField("Trigger phrase (for example: email signature)", text: $trigger)
                    TextEditor(text: $expansion)
                        .frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if expansion.isEmpty {
                                Text("Exact text to insert")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5).padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Add snippet") { add() }
                        .disabled(SnippetProcessor.normalize(trigger).isEmpty || expansion.isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 245)

            List {
                ForEach(snippets) { snippet in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.trigger).font(.headline)
                            Text(snippet.expansion)
                                .font(.callout).foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        Spacer()
                        Button(role: .destructive) { history.deleteSnippet(snippet) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .overlay {
                if snippets.isEmpty {
                    ContentUnavailableView(
                        "No snippets yet", systemImage: "text.badge.plus",
                        description: Text("Say a trigger phrase to insert an exact local expansion."))
                }
            }
        }
        .navigationTitle("Snippets")
    }

    private func add() {
        do {
            try history.addSnippet(trigger: trigger, expansion: expansion)
            trigger = ""
            expansion = ""
            errorMessage = nil
        } catch HistoryStore.SnippetError.duplicateTrigger {
            errorMessage = "That trigger already exists."
        } catch HistoryStore.SnippetError.dictionaryConflict {
            errorMessage = "That trigger conflicts with a dictionary correction."
        } catch {
            errorMessage = "Enter both a trigger and an expansion."
        }
    }
}
