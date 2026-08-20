import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appearance") private var appearance: String = "system"

    var body: some View {
        TabView {
            DeckListView()
                .tabItem {
                    Label("Decks", systemImage: "rectangle.stack")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(colorScheme)
        .task {
            SampleData.seedIfNeeded(modelContext: modelContext)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Deck.self, Card.self, SessionResult.self])
}