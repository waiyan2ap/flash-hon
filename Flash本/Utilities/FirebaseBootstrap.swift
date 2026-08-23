import Foundation
import FirebaseCore
import GoogleSignIn

enum FirebaseBootstrap {
    static private(set) var isConfigured = false

    static func configure() {
        guard !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        isConfigured = true
    }
}
