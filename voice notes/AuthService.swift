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

    // MARK: - Auth State

    var isSignedIn: Bool {
        userId != nil
    }

    var userId: String? {
        get { UserDefaults.standard.string(forKey: userIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: userIdKey) }
    }

    var userEmail: String? {
        get { UserDefaults.standard.string(forKey: userEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: userEmailKey) }
    }

    var userName: String? {
        get { UserDefaults.standard.string(forKey: userNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
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
                userId = appleIDCredential.user

                // Email and name are only provided on first sign-in
                if let email = appleIDCredential.email {
                    userEmail = email
                }

                if let fullName = appleIDCredential.fullName {
                    let name = [fullName.givenName, fullName.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    if !name.isEmpty {
                        userName = name
                    }
                }
            }

        case .failure(let error):
            print("Sign in with Apple failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Out

    func signOut() {
        // Only clear userId - keep userName/userEmail so they're restored on sign back in
        // Apple only provides name/email on FIRST sign-in, so we need to preserve them
        userId = nil

        // Note: Usage is NOT reset on sign out - user keeps their usage history
    }

    /// Clear all user data (for "Delete All Data" option)
    func clearAllUserData() {
        userId = nil
        userEmail = nil
        userName = nil
        UsageService.shared.resetAllUsage()
    }

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
                    break
                case .revoked, .notFound:
                    // User revoked access or account not found - sign out
                    self.signOut()
                case .transferred:
                    // Account was transferred to a different team
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

// MARK: - Sign In With Apple Button (using SwiftUI native)

// MARK: - Sign In View

struct SignInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let onSignedIn: () -> Void

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/branding
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Voice Notes")
                    .font(.largeTitle.weight(.bold))

                Text("Turn messy thoughts into\nresolved actions")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureItem(icon: "mic.fill", text: "Unlimited recording")
                FeatureItem(icon: "brain.head.profile", text: "AI-powered extraction")
                FeatureItem(icon: "icloud.fill", text: "Synced across devices")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Sign in button - using SwiftUI native
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    AuthService.shared.handleSignInResult(.success(authorization))
                    if AuthService.shared.isSignedIn {
                        onSignedIn()
                    }
                case .failure(let error):
                    print("Sign in failed: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            // Skip option
            Button("Continue without account") {
                // Allow using app without sign in (local only)
                onSignedIn()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Debug: Skip sign-in for simulator testing
            #if DEBUG
            Button("Debug: Skip to signed in") {
                // Simulate sign-in for testing
                AuthService.shared.userId = "debug-user"
                AuthService.shared.userName = "Test User"
                onSignedIn()
            }
            .font(.caption)
            .foregroundStyle(.orange)
            #endif
        }
        .padding(.bottom, 32)
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

struct FeatureItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    SignInView(onSignedIn: {})
}
