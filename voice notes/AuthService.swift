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
    private let eeonContextKey = "eeonContext"

    // MARK: - Stored Properties (observable)

    private(set) var userId: String?
    private(set) var userEmail: String?
    var userName: String? {
        didSet {
            UserDefaults.standard.set(userName, forKey: userNameKey)
        }
    }
    var eeonContext: String? {
        didSet {
            UserDefaults.standard.set(eeonContext, forKey: eeonContextKey)
        }
    }

    // MARK: - Init (load from UserDefaults)

    init() {
        // Load persisted values
        self.userId = UserDefaults.standard.string(forKey: userIdKey)
        self.userEmail = UserDefaults.standard.string(forKey: userEmailKey)
        self.userName = UserDefaults.standard.string(forKey: userNameKey)
        self.eeonContext = UserDefaults.standard.string(forKey: eeonContextKey)
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
        eeonContext = nil
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

    // MARK: - AI Context

    /// Returns the user's EEON context formatted for system prompt injection, or empty string if not set.
    var eeonContextPrefix: String {
        guard let ctx = eeonContext, !ctx.isEmpty else { return "" }
        return "About the user: \(ctx)\n\n"
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
    private var authService: AuthService { AuthService.shared }

    @State private var currentPage = 0
    @State private var showingError = false
    @State private var errorMessage = ""

    private let pageCount = 4

    private func advanceToPaywall() {
        Task {
            await SubscriptionManager.shared.updateSubscriptionStatus()
            await MainActor.run {
                if SubscriptionManager.shared.isSubscribed {
                    OnboardingState.set(.completed)
                } else {
                    OnboardingState.set(.needsPaywall)
                }
            }
        }
    }

    /// Skip sign-in entirely — go straight to the app with 5 free notes
    private func skipToApp() {
        OnboardingState.set(.completed)
    }

    var body: some View {
        ZStack {
            // Dark background with coral atmospheric glow
            Color("EEONBackground")
                .ignoresSafeArea()

            // Coral radial glow — shifts subtly per page
            RadialGradient(
                colors: [Color("EEONAccent").opacity(currentPage == 0 ? 0.25 : 0.12), Color("EEONAccent").opacity(0.04), Color.clear],
                center: currentPage == 0 ? .top : (currentPage == 1 ? .topTrailing : (currentPage == 2 ? .topLeading : .top)),
                startRadius: 20,
                endRadius: 500
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: currentPage)

            VStack(spacing: 0) {
                // Paged content
                TabView(selection: $currentPage) {
                    heroPage.tag(0)
                    recordPage.tag(1)
                    askPage.tag(2)
                    organizePage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator dots in coral
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color("EEONAccent") : Color("EEONTextPrimary").opacity(0.15))
                            .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }
                .padding(.bottom, 28)

                // Bottom action area
                VStack(spacing: 14) {
                    if currentPage < pageCount - 1 {
                        // Continue button — coral accent
                        Button {
                            withAnimation(.spring(response: 0.4)) { currentPage += 1 }
                        } label: {
                            Text("Continue")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color("EEONAccent"))
                                .cornerRadius(14)
                        }
                    } else {
                        // Final page: Sign in with Apple + skip
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

                        Button {
                            skipToApp()
                        } label: {
                            Text("Try 5 free notes first")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color("EEONTextSecondary"))
                                .underline()
                        }
                        .padding(.top, 4)
                    }
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

    // MARK: - Page 1: Hero

    private var heroPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Coral waveform icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(Color("EEONAccent").opacity(0.06))
                    .frame(width: 180, height: 180)
                    .blur(radius: 20)

                // Inner ring
                Circle()
                    .fill(Color("EEONAccent").opacity(0.10))
                    .frame(width: 120, height: 120)

                // Waveform bars
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array([0.4, 0.7, 1.0, 0.8, 0.5, 0.9, 0.6, 0.3, 0.75].enumerated()), id: \.offset) { _, scale in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color("EEONAccent"))
                            .frame(width: 4, height: CGFloat(scale) * 44)
                    }
                }
            }
            .padding(.bottom, 48)

            VStack(spacing: 14) {
                Text("Talk. Your AI\nremembers.")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color("EEONTextPrimary"))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("Voice notes that think for you")
                    .font(.system(size: 17))
                    .foregroundStyle(Color("EEONTextSecondary"))
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer().frame(height: 32)
        }
    }

    // MARK: - Page 2: Record + Live Transcript

    private var recordPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Recording mockup with waveform bars
            ZStack {
                // Glow
                Circle()
                    .fill(Color("EEONAccent").opacity(0.05))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                VStack(spacing: 16) {
                    // Waveform visualization
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(Array([0.3, 0.5, 0.8, 0.6, 1.0, 0.7, 0.9, 0.4, 0.6, 0.8, 0.5, 0.3].enumerated()), id: \.offset) { _, scale in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color("EEONAccent").opacity(0.7))
                                .frame(width: 3, height: CGFloat(scale) * 36)
                        }
                    }

                    // Mock transcript lines
                    VStack(alignment: .leading, spacing: 6) {
                        mockTranscriptLine(width: 140)
                        mockTranscriptLine(width: 100)
                        mockTranscriptLine(width: 120)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color("EEONTextPrimary").opacity(0.04))
                )
            }
            .padding(.bottom, 40)

            VStack(spacing: 14) {
                Text("Just talk")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color("EEONTextPrimary"))
                    .tracking(-0.5)

                Text("Your words appear in real-time.\nAI removes filler and enhances\nyour thoughts into clear notes.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color("EEONTextSecondary"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()
            Spacer().frame(height: 32)
        }
    }

    // MARK: - Page 3: Ask Your Memory

    private var askPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Chat bubble illustration
            ZStack {
                Circle()
                    .fill(Color("EEONAccent").opacity(0.05))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                VStack(spacing: 12) {
                    // User question bubble
                    HStack {
                        Spacer()
                        Text("What did I promise Sarah?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color("EEONAccent"))
                            )
                    }

                    // AI response bubble
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You promised to send the proposal by Friday and review her draft.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color("EEONTextPrimary").opacity(0.9))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color("EEONTextPrimary").opacity(0.06))
                        )
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 280)
            }
            .padding(.bottom, 40)

            VStack(spacing: 14) {
                Text("Ask anything")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color("EEONTextPrimary"))
                    .tracking(-0.5)

                Text("Search across all your notes\nwith AI that remembers everything.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color("EEONTextSecondary"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()
            Spacer().frame(height: 32)
        }
    }

    // MARK: - Page 4: AI Organizes

    private var organizePage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Organized sections illustration
            ZStack {
                Circle()
                    .fill(Color("EEONAccent").opacity(0.05))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                VStack(spacing: 8) {
                    organizeRow(icon: "flame.fill", label: "Active Threads", count: "3", color: Color("EEONAccent"))
                    organizeRow(icon: "exclamationmark.triangle.fill", label: "Needs Attention", count: "2", color: .orange)
                    organizeRow(icon: "person.2.fill", label: "People", count: "5", color: .blue)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color("EEONTextPrimary").opacity(0.04))
                )
                .frame(maxWidth: 260)
            }
            .padding(.bottom, 40)

            VStack(spacing: 14) {
                Text("Never drop\nthe ball")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color("EEONTextPrimary"))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("AI tracks your decisions,\ncommitments, and action items.\nGet reminded when things go stale.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color("EEONTextSecondary"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Spacer()
            Spacer().frame(height: 32)
        }
    }

    // MARK: - Helper Views

    private func mockTranscriptLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color("EEONTextPrimary").opacity(0.12))
            .frame(width: width, height: 8)
    }

    private func organizeRow(icon: String, label: String, count: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color("EEONTextPrimary").opacity(0.8))

            Spacer()

            Text(count)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color("EEONTextSecondary"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color("EEONTextPrimary").opacity(0.06))
                )
        }
    }
}

#Preview {
    SignInView()
}
