import SwiftUI

/// Main app window (spec §7): sidebar Home / History / Dictionary + Settings link.
struct HubView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "Home"
        case history = "History"
        case dictionary = "Dictionary"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "character.book.closed"
            }
        }
    }

    let history: HistoryStore?
    @State private var selection: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        } detail: {
            if let history {
                switch selection {
                case .home: HomeView(history: history)
                case .history: HistoryView(history: history)
                case .dictionary: DictionaryView(history: history)
                }
            } else {
                ContentUnavailableView("History unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Talkie couldn't open its local database."))
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}
