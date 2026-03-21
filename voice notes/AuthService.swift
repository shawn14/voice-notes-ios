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

// MARK: - Onboarding State Machine

/// Single source of truth for onboarding flow.
/// Persisted to UserDefaults via @AppStorage in voice_notesApp.
enum OnboardingState: String {
    case needsSignIn    // Show sign-in carousel
    case needsPaywall   // Show subscription paywall
    case completed      // Show main app

    private static let key = "onboardingState"

    /// Read current state from UserDefaults
    static var current: OnboardingState {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let state = OnboardingState(rawValue: raw) else {
            return .needsSignIn
        }
        return state
    }

    /// Write state to UserDefaults (triggers @AppStorage updates)
    static func set(_ state: OnboardingState) {
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }
}

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
        // Clear cached subscription status (isPro requires isSignedIn anyway,
        // but this prevents stale "pro" status leaking across sign-in cycles)
        UsageService.shared.downgradeToFree()
        OnboardingState.set(.needsSignIn)
        print("Signed out. isSignedIn: \(isSignedIn)")
    }

    /// Clear all user data (for "Delete All Data" option)
    func clearAllUserData() {
        setUserId(nil)
        setUserEmail(nil)
        userName = nil
        UsageService.shared.resetAllUsage()
        OnboardingState.set(.needsSignIn)
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
    private var authService: AuthService { AuthService.shared }

    @State private var currentPage = 0
    @State private var showingError = false
    @State private var errorMessage = ""

    private let pageCount = 3

    private func advanceToPaywall() {
        OnboardingState.set(.needsPaywall)
    }

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

                // Page indicator — refined capsule bars
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.15))
                            .frame(width: index == currentPage ? 28 : 8, height: 3)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }
                .padding(.bottom, 24)

                // Bottom action area
                VStack(spacing: 14) {
                    if currentPage < pageCount - 1 {
                        Button {
                            withAnimation(.spring(response: 0.4)) { currentPage += 1 }
                        } label: {
                            Text("Continue")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
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
                                if authService.isSignedIn { advanceToPaywall() }
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .cornerRadius(14)
                    }

                    Button("Skip") { advanceToPaywall() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)

                #if DEBUG
                Button {
                    authService.debugSignIn()
                    advanceToPaywall()
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
                // Deep blue atmosphere — layered for depth
                RadialGradient(
                    colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.08), Color.clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 550
                )
                RadialGradient(
                    colors: [Color.cyan.opacity(0.1), Color.clear],
                    center: .bottomLeading,
                    startRadius: 50,
                    endRadius: 400
                )
            case 1:
                // Warm purple atmosphere — richer, more dramatic
                RadialGradient(
                    colors: [Color.purple.opacity(0.35), Color.purple.opacity(0.08), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 500
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.12), Color.clear],
                    center: .bottomLeading,
                    startRadius: 80,
                    endRadius: 400
                )
            default:
                // Teal atmosphere — deeper, more confident
                RadialGradient(
                    colors: [Color.cyan.opacity(0.25), Color.teal.opacity(0.08), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 500
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.1), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 80,
                    endRadius: 400
                )
            }
        }
    }

    // MARK: - Page 1: Capture

    private var page1: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon with layered glow
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.05))
                    .frame(width: 180, height: 180)
                    .blur(radius: 20)

                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: 100, height: 100)

                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 44)

            VStack(spacing: 14) {
                Text("Just talk.")
                    .font(.system(size: 38, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .tracking(-0.5)

                Text("We turn your voice into\norganized, searchable notes.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()

            // Feature hints with subtle glass backing
            VStack(spacing: 12) {
                featureRow("waveform", "Record anywhere")
                featureRow("text.cursor", "Transcribed instantly")
                featureRow("arrow.trianglehead.2.clockwise", "Synced to all devices")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
            )
            .padding(.horizontal, 28)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Page 2: AI

    private var page2: some View {
        VStack(spacing: 0) {
            Spacer()

            // Sparkle cluster — larger, more depth
            ZStack {
                // Soft glow behind
                Circle()
                    .fill(Color.purple.opacity(0.06))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                Image(systemName: "sparkle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.25))
                    .offset(x: -44, y: -34)

                Image(systemName: "sparkle")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: 48, y: -42)

                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.12))
                    .offset(x: 52, y: 22)

                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(height: 130)
            .padding(.bottom, 40)

            VStack(spacing: 14) {
                Text("AI does the rest.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.5)

                Text("Decisions, actions, commitments —\nextracted from every note.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()

            VStack(spacing: 12) {
                featureRow("checkmark.circle", "Actions from your words")
                featureRow("person.2", "Tracks who owes what")
                featureRow("exclamationmark.circle", "Flags what needs attention")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
            )
            .padding(.horizontal, 28)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Page 3: Reports

    private var page3: some View {
        VStack(spacing: 0) {
            Spacer()

            // Abstract chart visualization — more refined
            ZStack {
                // Soft glow
                Circle()
                    .fill(Color.cyan.opacity(0.06))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(Array([0.3, 0.5, 0.72, 0.48, 0.88, 0.62, 0.4].enumerated()), id: \.offset) { index, height in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.7), .blue.opacity(0.25)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 14, height: CGFloat(height) * 90)
                    }
                }
                .frame(height: 100)
            }
            .padding(.bottom, 40)

            VStack(spacing: 14) {
                Text("Your command\ncenter.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("CEO reports, SWOT analysis,\ngoal tracking — one tap away.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()

            VStack(spacing: 12) {
                featureRow("chart.bar.doc.horizontal", "AI-powered reports")
                featureRow("rectangle.3.group", "Visual project boards")
                featureRow("target", "Track goals & momentum")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
            )
            .padding(.horizontal, 28)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Feature Row (minimal, no cards)

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 24, height: 24)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))

            Spacer()
        }
    }
}

#Preview {
    SignInView()
}
