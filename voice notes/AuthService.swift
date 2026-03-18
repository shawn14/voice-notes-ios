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

// MARK: - Sign In View

struct SignInView: View {
    let onSignedIn: () -> Void

    private var authService: AuthService { AuthService.shared }

    @State private var currentPage = 0
    @State private var showingError = false
    @State private var errorMessage = ""

    private let pageCount = 3

    var body: some View {
        ZStack {
            // Atmospheric gradient background that shifts per page
            backgroundGradient
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: currentPage)

            VStack(spacing: 0) {
                // Paged content
                TabView(selection: $currentPage) {
                    page1.tag(0)
                    page2.tag(1)
                    page3.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator — thin bars, not dots
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.2))
                            .frame(width: index == currentPage ? 24 : 8, height: 4)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }
                .padding(.bottom, 28)

                // Bottom action area
                VStack(spacing: 12) {
                    if currentPage < pageCount - 1 {
                        Button {
                            withAnimation(.spring(response: 0.4)) { currentPage += 1 }
                        } label: {
                            Text("Continue")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(14)
                        }
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                authService.handleSignInResult(.success(authorization))
                                if authService.isSignedIn { onSignedIn() }
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .cornerRadius(14)
                    }

                    Button("Skip") { onSignedIn() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)

                #if DEBUG
                Button {
                    authService.debugSignIn()
                    onSignedIn()
                } label: {
                    Text("Debug Sign In")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.top, 12)
                #endif

                Spacer().frame(height: 20)
            }
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color.black

            switch currentPage {
            case 0:
                // Deep blue atmosphere
                RadialGradient(
                    colors: [Color.blue.opacity(0.25), Color.clear],
                    center: .top,
                    startRadius: 100,
                    endRadius: 500
                )
            case 1:
                // Warm purple atmosphere
                RadialGradient(
                    colors: [Color.purple.opacity(0.2), Color.clear],
                    center: .topTrailing,
                    startRadius: 80,
                    endRadius: 450
                )
            default:
                // Teal atmosphere
                RadialGradient(
                    colors: [Color.cyan.opacity(0.15), Color.clear],
                    center: .topLeading,
                    startRadius: 100,
                    endRadius: 500
                )
            }
        }
    }

    // MARK: - Page 1: Capture

    private var page1: some View {
        VStack(spacing: 0) {
            Spacer()

            // Large icon with glow
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: "mic.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)

            // Typography-forward layout
            VStack(spacing: 16) {
                Text("Just talk.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text("We turn your voice into\norganized, searchable notes.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            // Minimal feature hints — no cards, just clean text
            VStack(spacing: 18) {
                featureRow("waveform", "Record anywhere")
                featureRow("text.cursor", "Transcribed instantly")
                featureRow("arrow.trianglehead.2.clockwise", "Synced to all devices")
            }
            .padding(.horizontal, 48)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Page 2: AI

    private var page2: some View {
        VStack(spacing: 0) {
            Spacer()

            // Sparkle cluster
            ZStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
                    .offset(x: -40, y: -30)

                Image(systemName: "sparkle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.2))
                    .offset(x: 45, y: -40)

                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.15))
                    .offset(x: 50, y: 20)

                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(height: 120)
            .padding(.bottom, 36)

            VStack(spacing: 16) {
                Text("AI does the rest.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Text("Decisions, actions, commitments —\nextracted from every note.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            VStack(spacing: 18) {
                featureRow("checkmark.circle", "Actions from your words")
                featureRow("person.2", "Tracks who owes what")
                featureRow("exclamationmark.circle", "Flags what needs attention")
            }
            .padding(.horizontal, 48)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Page 3: Reports

    private var page3: some View {
        VStack(spacing: 0) {
            Spacer()

            // Abstract chart visualization
            ZStack {
                // Layered bars suggesting a report/dashboard
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach([0.35, 0.55, 0.7, 0.5, 0.85, 0.65, 0.45], id: \.self) { height in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.6), .blue.opacity(0.3)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 12, height: CGFloat(height) * 80)
                    }
                }
                .frame(height: 90)
            }
            .padding(.bottom, 36)

            VStack(spacing: 16) {
                Text("Your command\ncenter.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("CEO reports, SWOT analysis,\ngoal tracking — one tap away.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            VStack(spacing: 18) {
                featureRow("chart.bar.doc.horizontal", "AI-powered reports")
                featureRow("rectangle.3.group", "Visual project boards")
                featureRow("target", "Track goals & momentum")
            }
            .padding(.horizontal, 48)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Feature Row (minimal, no cards)

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 22)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
    }
}

#Preview {
    SignInView(onSignedIn: {})
}
