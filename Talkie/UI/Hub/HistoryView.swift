import SwiftUI

struct HistoryView: View {
    let history: HistoryStore

    var body: some View {
        ContentUnavailableView("History", systemImage: "clock.arrow.circlepath",
                               description: Text("Arrives in the next task."))
    }
}
