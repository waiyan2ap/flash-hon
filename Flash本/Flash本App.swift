import SwiftUI
import SwiftData
import GoogleSignIn

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
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(container)
    }
}
