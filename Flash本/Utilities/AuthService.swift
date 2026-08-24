import Foundation
import FirebaseAuth
import AuthenticationServices
import GoogleSignIn
import CryptoKit
import Observation

@MainActor
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    private(set) var user: User?
    private(set) var isBusy = false
    var errorMessage: String?

    var isSignedIn: Bool { user != nil }
    var userEmail: String? { user?.email }
    var uid: String? { user?.uid }

    private var currentNonce: String?

    private init() {
        guard FirebaseBootstrap.isConfigured else { return }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasSignedIn = self.user != nil
                self.user = user
                if user != nil, !wasSignedIn {
                    SyncEngine.shared.scheduleSync()
                } else if user == nil, wasSignedIn {
                    SyncEngine.shared.handleSignOut()
                }
            }
        }
    }

    func signIn(email: String, password: String) {
        guard ensureConfigured(), !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.errorMessage = Self.friendlyError(error)
                }
            }
        }
    }

    func signUp(email: String, password: String) {
        guard ensureConfigured(), !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.errorMessage = Self.friendlyError(error)
                }
            }
        }
    }

    func resetPassword(email: String) {
        guard ensureConfigured(), !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.errorMessage = Self.friendlyError(error)
                } else {
                    self.errorMessage = "Password reset email sent. Check your inbox."
                }
            }
        }
    }

    func signOut() {
        guard ensureConfigured() else { return }
        errorMessage = nil
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = Self.friendlyError(error)
        }
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleApple(result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    return
                case .unknown:
                    errorMessage = "Apple sign-in was interrupted. Please try again."
                    return
                default:
                    break
                }
            }
            errorMessage = Self.friendlyError(error)
        case .success(let authorization):
            guard ensureConfigured(),
                  let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleIDCredential.identityToken,
                  let idToken = String(data: idTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Unable to sign in with Apple."
                return
            }
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            authSignIn(with: credential)
        }
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() {
        guard ensureConfigured(), !isBusy else { return }
        errorMessage = nil

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else {
            errorMessage = "Could not present Google sign in."
            return
        }

        isBusy = true
        GIDSignIn.sharedInstance.signIn(withPresenting: root) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.isBusy = false
                    if (error as? GIDSignInError)?.code != .canceled {
                        self.errorMessage = Self.friendlyError(error)
                    }
                    return
                }
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.isBusy = false
                    self.errorMessage = "Google sign in failed."
                    return
                }
                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )
                self.authSignIn(with: credential)
            }
        }
    }

    // MARK: - Helpers

    private func authSignIn(with credential: AuthCredential) {
        Auth.auth().signIn(with: credential) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.errorMessage = Self.friendlyError(error)
                }
            }
        }
    }

    private func ensureConfigured() -> Bool {
        guard FirebaseBootstrap.isConfigured else {
            errorMessage = "Cloud sync unavailable."
            return false
        }
        return true
    }

    nonisolated static func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError

        switch AuthErrorCode(rawValue: nsError.code) {
        case .invalidEmail: return "That email address looks invalid."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Incorrect email or password."
        case .emailAlreadyInUse: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 6 characters."
        case .tooManyRequests: return "Too many attempts. Try again later."
        case .networkError: return "Network error. Check your connection."
        case .userDisabled: return "This account has been disabled."
        case .operationNotAllowed: return "This sign-in method isn't enabled in Firebase yet."
        default: break
        }

        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            return reason
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           let message = underlying.userInfo[NSLocalizedDescriptionKey] as? String, !message.isEmpty {
            return message
        }

        let description = nsError.localizedDescription
        if description.isEmpty || description == "The operation couldn't be completed." {
            return "Sign-in failed. Please try again."
        }
        return description
    }

    private nonisolated static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
