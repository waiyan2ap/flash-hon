import SwiftUI
import SwiftData
import AuthenticationServices

struct AccountView: View {
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showSignOutConfirm = false
    @FocusState private var focusedField: Field?

    enum AuthMode {
        case signIn
        case createAccount

        var isSignIn: Bool { self == .signIn }
    }

    enum Field: Hashable {
        case email
        case password
        case confirm
    }

    private var auth: AuthService { AuthService.shared }
    private var sync: SyncEngine { SyncEngine.shared }

    var body: some View {
        Group {
            if !FirebaseBootstrap.isConfigured {
                unconfiguredView
            } else if auth.isSignedIn {
                signedInView
            } else {
                authScreen
            }
        }
        .navigationTitle(auth.isSignedIn ? "Account" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Unconfigured (no GoogleService-Info.plist yet)

    private var unconfiguredView: some View {
        ContentUnavailableView(
            "Cloud Sync Unavailable",
            systemImage: "icloud.slash",
            description: Text("Firebase hasn't been set up for this build yet. All data stays safely on this device.")
        )
    }

    // MARK: - Signed out

    private var authScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                brandingHeader

                inputCard

                if let error = auth.errorMessage {
                    errorBanner(error)
                }

                primaryButton

                if mode.isSignIn {
                    forgotPasswordLink
                }

                orDivider

                socialButtons

                Spacer(minLength: 8)

                modeToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var brandingHeader: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 86, height: 86)
                .overlay(
                    Image(systemName: "book.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.accentColor)
                )

            VStack(spacing: 6) {
                Text("FlashHon")
                    .font(.largeTitle.bold())

                Text(mode.isSignIn
                    ? "Welcome back"
                    : "Create your account")

                Text("Sync your decks and study history across devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, 8)
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()

            HStack {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                SecureField("Password", text: $password)
                    .textContentType(mode.isSignIn ? .password : .newPassword)
                    .submitLabel(mode.isSignIn ? .go : .next)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        if mode.isSignIn {
                            submitForm()
                        } else {
                            focusedField = .confirm
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if !mode.isSignIn {
                Divider()

                HStack {
                    Image(systemName: "lock.rotation")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .confirm)
                        .onSubmit { submitForm() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var primaryButton: some View {
        Button(action: submitForm) {
            HStack(spacing: 8) {
                if auth.isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(mode.isSignIn ? "Sign In" : "Create Account")
                    .bold()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isFormValid || auth.isBusy)
    }

    private var forgotPasswordLink: some View {
        Button("Forgot Password?") {
            let clean = email.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { return }
            auth.resetPassword(email: clean)
        }
        .font(.footnote)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 0.5)
            Text("or continue with")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                auth.handleApple(result: result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(Capsule())
            .disabled(auth.isBusy)

            Button {
                auth.signInWithGoogle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text("Continue with Google")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .disabled(auth.isBusy)
        }
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = mode.isSignIn ? .createAccount : .signIn
                auth.errorMessage = nil
                confirmPassword = ""
            }
        } label: {
            HStack(spacing: 4) {
                Text(mode.isSignIn
                    ? "Don't have an account?"
                    : "Already have an account?")
                    .foregroundStyle(.secondary)
                Text(mode.isSignIn
                    ? "Create one"
                    : "Sign in")
                    .bold()
            }
            .font(.subheadline)
        }
    }

    // MARK: - Signed in

    private var signedInView: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    avatarCircle

                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.userEmail ?? "Signed in")
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        Label("Cloud sync active", systemImage: "checkmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Sync") {
                HStack {
                    Text("Last synced")
                    Spacer()
                    if sync.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(sync.lastSyncedText)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await sync.syncNow() }
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if sync.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(sync.isSyncing)

                if let error = sync.syncError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Text("Sign Out")
                }
            }
        }
        .confirmationDialog(
            "Sign out of this device?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data stays on this device. Signing back in resumes syncing.")
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
            Text(String((auth.userEmail?.first ?? "?").uppercased()))
                .font(.title3.bold())
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 48, height: 48)
    }

    // MARK: - Logic

    private var isFormValid: Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespaces)
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { return false }
        guard password.count >= 6 else { return false }
        if !mode.isSignIn && password != confirmPassword { return false }
        return true
    }

    private func submitForm() {
        focusedField = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        switch mode {
        case .signIn:
            auth.signIn(email: cleanEmail, password: password)
        case .createAccount:
            auth.signUp(email: cleanEmail, password: password)
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
    }
}
