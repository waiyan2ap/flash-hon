import SwiftUI
import SwiftData

@main
struct FlashApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Deck.self, Card.self, SessionResult.self])
    }
}