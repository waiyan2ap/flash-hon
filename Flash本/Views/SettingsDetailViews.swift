import SwiftUI
import SwiftData

struct StatisticsDetailView: View {
    @Query(sort: \SessionResult.date, order: .reverse) private var allSessions: [SessionResult]

    var body: some View {
        List {
            if allSessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Complete a study session to see your stats.")
                )
            } else {
                Section("Today") {
                    dailySection(for: .now)
                }
                Section("Yesterday") {
                    dailySection(for: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
                }
                Section("This Week") {
                    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
                    let sessions = allSessions.filter { $0.date >= weekAgo }
                    statRows(for: sessions)
                }
                Section("All Time") {
                    statRows(for: allSessions)
                }
                Section("Recent Sessions") {
                    ForEach(allSessions.prefix(10)) { session in
                        HStack {
                            Text(session.deckName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(session.correctCount)/\(session.totalCount)")
                                .font(.subheadline.bold())
                            Text(relativeTime(session.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistics")
    }

    private func dailySection(for date: Date) -> some View {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return AnyView(EmptyView())
        }
        let sessions = allSessions.filter { $0.date >= dayStart && $0.date < dayEnd }
        return AnyView(statRows(for: sessions))
    }

    private func statRows(for sessions: [SessionResult]) -> some View {
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctCount }
        let totalQuestions = sessions.reduce(0) { $0 + $1.totalCount }
        let accuracy = totalQuestions > 0 ? Double(totalCorrect) / Double(totalQuestions) : 0
        return Group {
            StatRow(label: "Sessions", value: "\(sessions.count)")
            StatRow(label: "Correct", value: "\(totalCorrect)/\(totalQuestions) (\(Int(accuracy * 100))%)")
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

struct AppearanceView: View {
    @AppStorage("appearance") private var appearance: String = "system"

    var body: some View {
        List {
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Appearance")
    }
}

struct ResetDataView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section {
                Button("Reset All Data", role: .destructive) {
                    showResetAlert = true
                }
            } footer: {
                Text("Deletes all decks, cards, and session history permanently.")
            }
        }
        .navigationTitle("Reset Data")
        .alert("Reset All Data", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { deleteAll() }
        } message: {
            Text("This will delete all decks, cards, and session history. This cannot be undone.")
        }
    }

    private func deleteAll() {
        let sessionDescriptor = FetchDescriptor<SessionResult>()
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            for session in sessions {
                modelContext.delete(session)
            }
        }
        let deckDescriptor = FetchDescriptor<Deck>()
        if let decks = try? modelContext.fetch(deckDescriptor) {
            for deck in decks {
                modelContext.delete(deck)
            }
        }
        try? modelContext.save()
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsDetailView()
            .modelContainer(for: [SessionResult.self])
    }
}