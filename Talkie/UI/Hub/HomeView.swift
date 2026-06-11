import SwiftUI

/// Hub landing page (spec §7): greeting, shortcut reminder, stats, recent dictations.
struct HomeView: View {
    let history: HistoryStore
    @State private var stats = HistoryStore.Stats(totalWords: 0, totalDuration: 0,
                                                  dictationsToday: 0, streakDays: 0)
    @State private var recent: [DictationRecord] = []

    /// Minutes you'd still be typing: time-to-type at 45wpm minus time spent speaking.
    static func minutesSaved(words: Int, duration: TimeInterval) -> Int {
        max(0, Int((Double(words) / 45.0) - (duration / 60.0)))
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.largeTitle.bold())
                    Text("Hold **fn** and speak — double-tap fn for hands-free.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    statCard(value: "\(stats.totalWords)", label: "words dictated")
                    statCard(value: "\(Self.minutesSaved(words: stats.totalWords, duration: stats.totalDuration))",
                             label: "min saved vs typing")
                    statCard(value: "\(stats.streakDays)", label: "day streak") // spec §7
                    statCard(value: "\(stats.dictationsToday)", label: "dictations today")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent").font(.title3.bold())
                    if recent.isEmpty {
                        Text("No dictations yet — hold fn and say something.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recent) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.cleanedText.isEmpty ? "(\(record.status.rawValue))" : record.cleanedText)
                                .lineLimit(2)
                            Text("\(record.appName ?? "Unknown app") · \(record.date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Home")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        stats = history.stats()
        recent = history.recent(limit: 5)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
