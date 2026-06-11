import SwiftUI

struct DictionaryView: View {
    let history: HistoryStore

    var body: some View {
        ContentUnavailableView("Dictionary", systemImage: "character.book.closed",
                               description: Text("Arrives in a later task."))
    }
}
