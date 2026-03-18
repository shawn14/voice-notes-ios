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

// MARK: - Onboarding Page Model

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let features: [(icon: String, text: String)]
    let screenshotName: String? // Asset catalog image name, nil = show icon instead
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "mic.fill",
        iconColor: .blue,
        title: "Capture Everything",
        subtitle: "Just talk. Your voice becomes searchable, organized notes — automatically.",
        features: [
            (icon: "waveform", text: "Record anytime, anywhere"),
            (icon: "text.alignleft", text: "Instant transcription"),
            (icon: "clock.fill", text: "Unlimited recording time")
        ],
        screenshotName: "onboarding_capture" // Add to Assets.xcassets
    ),
    OnboardingPage(
        icon: "sparkles",
        iconColor: .blue,
        title: "AI Does the Work",
        subtitle: "Decisions, action items, commitments — extracted instantly from every note.",
        features: [
            (icon: "checkmark.circle.fill", text: "Actions pulled from your words"),
            (icon: "person.2.fill", text: "Tracks who owes what"),
            (icon: "brain.head.profile", text: "Surfaces what needs attention")
        ],
        screenshotName: "onboarding_ai" // Add to Assets.xcassets
    ),
    OnboardingPage(
        icon: "chart.bar.doc.horizontal.fill",
        iconColor: .blue,
        title: "Stay on Top of It All",
        subtitle: "CEO reports, goal tracking, project status — one tap from your voice notes.",
        features: [
            (icon: "rectangle.3.group.fill", text: "Visual project boards"),
            (icon: "doc.text.magnifyingglass", text: "AI-powered reports"),
            (icon: "icloud.fill", text: "Synced across all devices")
        ],
        screenshotName: "onboarding_reports" // Add to Assets.xcassets
    )
]

// MARK: - Sign In View

struct SignInView: View {
    let onSignedIn: () -> Void

    private var authService: AuthService { AuthService.shared }

    @State private var currentPage = 0
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Paged walkthrough
                TabView(selection: $currentPage) {
                    ForEach(Array(onboardingPages.enumerated()), id: \.element.id) { index, page in
                        onboardingPageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)

                // Sign in section
                VStack(spacing: 14) {
                    if currentPage < onboardingPages.count - 1 {
                        // "Next" button on first pages
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            Text("Next")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    } else {
                        // Sign in on last page
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
                    }

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
                .padding(.horizontal, 32)
                #endif

                Spacer().frame(height: 24)
            }
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Onboarding Page

    private func onboardingPageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Hero: screenshot or icon fallback
            if let screenshotName = page.screenshotName,
               UIImage(named: screenshotName) != nil {
                // App screenshot in a phone frame
                Image(screenshotName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .cornerRadius(20)
                    .shadow(color: page.iconColor.opacity(0.3), radius: 20, y: 10)
                    .padding(.horizontal, 48)
            } else {
                // SF Symbol fallback
                ZStack {
                    Circle()
                        .fill(page.iconColor.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: page.icon)
                        .font(.system(size: 42))
                        .foregroundStyle(page.iconColor)
                }
            }

            // Title & subtitle
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
            }

            Spacer().frame(height: 4)

            // Feature cards
            VStack(spacing: 10) {
                ForEach(page.features, id: \.text) { feature in
                    HStack(spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        Text(feature.text)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.9))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    SignInView(onSignedIn: {})
}
