//
//  AuthService.swift
//  voice notes
//
//  Handles Sign in with Apple authentication
//

import Foundation
import AuthenticationServices
import SwiftUI
import UIKit

@Observable
class AuthService {
    static let shared = AuthService()

    private let userIdKey = "appleUserID"
    private let userEmailKey = "appleUserEmail"
    private let userNameKey = "appleUserName"

    // MARK: - Stored Properties (observable)

    private(set) var userId: String?
    private(set) var userEmail: String?
    var userName: String? {
        didSet {
            UserDefaults.standard.set(userName, forKey: userNameKey)
        }
    }

    // MARK: - Init (load from UserDefaults)

    init() {
        // Load persisted values
        self.userId = UserDefaults.standard.string(forKey: userIdKey)
        self.userEmail = UserDefaults.standard.string(forKey: userEmailKey)
        self.userName = UserDefaults.standard.string(forKey: userNameKey)
    }

    // MARK: - Computed Properties

    var isSignedIn: Bool {
        userId != nil
    }

    var displayName: String {
        userName ?? userEmail ?? "User"
    }

    // MARK: - Sign In

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                // Store user ID (always provided)
                setUserId(appleIDCredential.user)

                // Email and name are only provided on first sign-in
                if let email = appleIDCredential.email {
                    setUserEmail(email)
                }

                if let fullName = appleIDCredential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    if !name.isEmpty {
                        userName = name
                    }
                }

                print("Sign in successful. userId: \(userId ?? "nil"), isSignedIn: \(isSignedIn)")
            }

        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Setters (update both stored property and UserDefaults)

    private func setUserId(_ value: String?) {
        userId = value
        UserDefaults.standard.set(value, forKey: userIdKey)
    }

    private func setUserEmail(_ value: String?) {
        userEmail = value
        UserDefaults.standard.set(value, forKey: userEmailKey)
    }

    // MARK: - Sign Out

    func signOut() {
        // Only clear userId - keep userName/userEmail so they're restored on sign back in
        // Apple only provides name/email on FIRST sign-in, so we need to preserve them
        setUserId(nil)

        // Note: Usage is NOT reset on sign out - user keeps their usage history
        print("Signed out. isSignedIn: \(isSignedIn)")
    }

    /// Clear all user data (for "Delete All Data" option)
    func clearAllUserData() {
        setUserId(nil)
        setUserEmail(nil)
        userName = nil
        UsageService.shared.resetAllUsage()
    }

    #if DEBUG
    /// Debug-only method to simulate sign-in for testing
    func debugSignIn() {
        setUserId("debug-user")
        userName = "Test User"
        print("Debug sign in. userId: \(userId ?? "nil"), isSignedIn: \(isSignedIn)")
    }
    #endif

    // MARK: - Credential State Check

    func checkCredentialState() async {
        guard let userId = userId else { return }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)

            await MainActor.run {
                switch state {
                case .authorized:
                    // Still valid
                    print("Credential state: authorized")
                    break
                case .revoked, .notFound:
                    // User revoked access or account not found - sign out
                    print("Credential state: revoked or not found - signing out")
                    self.signOut()
                case .transferred:
                    // Account was transferred to a different team
                    print("Credential state: transferred")
                    break
                @unknown default:
                    break
                }
            }
        } catch {
            print("Failed to check credential state: \(error)")
        }
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onSignedIn: () -> Void

    private var authService: AuthService { AuthService.shared }

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Mic icon
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 100, height: 100)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                // Copy
                VStack(spacing: 12) {
                    Text("Voice Notes")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Talk it out. We'll handle the rest.")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }

                Spacer()

                // Simple features
                VStack(alignment: .leading, spacing: 20) {
                    SignInFeatureRow(icon: "waveform", text: "Record your thoughts")
                    SignInFeatureRow(icon: "sparkles", text: "AI extracts the action items")
                    SignInFeatureRow(icon: "icloud", text: "Synced everywhere")
                }
                .padding(.horizontal, 48)

                Spacer()

                // Sign in
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            authService.handleSignInResult(.success(authorization))
                            if authService.isSignedIn {
                                onSignedIn()
                            }
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)

                    Button("Skip for now") {
                        onSignedIn()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                }
                .padding(.horizontal, 32)

                #if DEBUG
                Button {
                    authService.debugSignIn()
                    onSignedIn()
                } label: {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("Debug Sign In (Simulator)")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
                #endif
            }
            .padding(.bottom, 32)
        }
                .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

private struct SignInFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

#Preview {
    SignInView(onSignedIn: {})
}
