import SwiftUI
import SwiftData

@main
struct FlashApp: App {
    let container: ModelContainer

    init() {
        FirebaseBootstrap.configure()
        do {
            container = try ModelContainer(for: Deck.self, Card.self, SessionResult.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        SyncEngine.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
