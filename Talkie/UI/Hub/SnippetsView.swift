import SwiftData
import SwiftUI

struct SnippetFormState {
    var errorMessage: String?
    var trigger = "" {
        didSet {
            if trigger != oldValue { errorMessage = nil }
        }
    }
    var expansion = "" {
        didSet {
            if expansion != oldValue { errorMessage = nil }
        }
    }

    static func deleteAccessibilityLabel(trigger: String) -> String {
        "Delete snippet \(trigger)"
    }
}

struct SnippetsView: View {
    let history: HistoryStore
    @Query(sort: \Snippet.trigger) private var snippets: [Snippet]
    @State private var form = SnippetFormState()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add a voice snippet") {
                    TextField("Trigger phrase (for example: email signature)", text: $form.trigger)
                    TextEditor(text: $form.expansion)
                        .frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if form.expansion.isEmpty {
                                Text("Exact text to insert")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5).padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    if let errorMessage = form.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Add snippet") { add() }
                        .disabled(SnippetProcessor.normalize(form.trigger).isEmpty || form.expansion.isEmpty)
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
                        .accessibilityLabel(
                            SnippetFormState.deleteAccessibilityLabel(trigger: snippet.trigger)
                        )
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
            try history.addSnippet(trigger: form.trigger, expansion: form.expansion)
            form.trigger = ""
            form.expansion = ""
            form.errorMessage = nil
        } catch HistoryStore.SnippetError.duplicateTrigger {
            form.errorMessage = "That trigger already exists."
        } catch HistoryStore.SnippetError.dictionaryConflict {
            form.errorMessage = "That trigger conflicts with a dictionary correction."
        } catch {
            form.errorMessage = "Enter both a trigger and an expansion."
        }
    }
}
