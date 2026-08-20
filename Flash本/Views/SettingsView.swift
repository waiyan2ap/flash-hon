import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: StatisticsDetailView()) {
                    Label("Statistics", systemImage: "chart.bar")
                }
                NavigationLink(destination: AppearanceView()) {
                    Label("Appearance", systemImage: "paintbrush")
                }
                NavigationLink(destination: ResetDataView()) {
                    Label("Reset Data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [SessionResult.self])
}