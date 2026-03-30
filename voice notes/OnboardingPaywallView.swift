//
//  OnboardingPaywallView.swift
//  voice notes
//
//  Timeline-based transparent onboarding paywall — shows users
//  what the free tier includes before they start.
//

import SwiftUI
import StoreKit
import AuthenticationServices

// MARK: - Timeline Step Component

struct TimelineStep: View {
    let emoji: String
    let isActive: Bool
    let title: String
    let subtitle: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: circle + connecting line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color("EEONAccent").opacity(0.15) : Color(.systemGray5))
                        .frame(width: 48, height: 48)
                    Text(emoji)
                        .font(.system(size: 22))
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2, height: 40)
                }
            }

            // Right: text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color("EEONTextPrimary"))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Onboarding Paywall View

struct OnboardingPaywallView: View {

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedPlan: SubscriptionProduct = .annual
    @State private var isPurchasing = false

    private let authService = AuthService.shared
    private let subscriptionManager = SubscriptionManager.shared

    var body: some View {
        ZStack {
            Color("EEONBackground").ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button — top left
                HStack {
                    Button {
                        OnboardingState.set(.completed)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color("EEONTextPrimary").opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5).opacity(0.6))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // Hero emoji
                        Text("\u{1f3a4}")
                            .font(.system(size: 80))
                            .padding(.top, 24)
                            .padding(.bottom, 20)

                        // Headline — "See how free works" with coral "free"
                        (
                            Text("See how ")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Color("EEONTextPrimary"))
                            + Text("free")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Color("EEONAccent"))
                            + Text(" works")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Color("EEONTextPrimary"))
                        )
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 36)

                        // Timeline section
                        VStack(spacing: 0) {
                            TimelineStep(
                                emoji: "\u{1f399}\u{fe0f}",
                                isActive: true,
                                title: "Today \u{2014} start recording",
                                subtitle: "5 free voice notes with full AI enhancement",
                                isLast: false
                            )

                            TimelineStep(
                                emoji: "\u{2728}",
                                isActive: false,
                                title: "Hit the limit",
                                subtitle: "Love it? Upgrade for unlimited notes and AI memory",
                                isLast: false
                            )

                            TimelineStep(
                                emoji: "\u{1f680}",
                                isActive: false,
                                title: "Go unlimited",
                                subtitle: "Ask your memory anything. Never forget what matters.",
                                isLast: true
                            )
                        }
                        .padding(.horizontal, 28)

                        Spacer().frame(height: 40)
                    }
                }

                // Bottom pinned section — plan selection + purchase
                VStack(spacing: 12) {
                    // Plan selector
                    HStack(spacing: 12) {
                        // Annual plan
                        Button {
                            selectedPlan = .annual
                        } label: {
                            VStack(spacing: 4) {
                                Text("Annual")
                                    .font(.subheadline.weight(.semibold))
                                Text("$79.99/yr")
                                    .font(.caption.weight(.medium))
                                Text("$6.67/mo")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(selectedPlan == .annual ? .white : Color("EEONTextPrimary"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedPlan == .annual ? Color("EEONAccent") : Color(.systemGray5).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedPlan == .annual ? Color("EEONAccent") : Color(.systemGray4), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)

                        // Monthly plan
                        Button {
                            selectedPlan = .monthly
                        } label: {
                            VStack(spacing: 4) {
                                Text("Monthly")
                                    .font(.subheadline.weight(.semibold))
                                Text("$9.99/mo")
                                    .font(.caption.weight(.medium))
                                Text(" ")
                                    .font(.caption2)
                            }
                            .foregroundStyle(selectedPlan == .monthly ? .white : Color("EEONTextPrimary"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedPlan == .monthly ? Color("EEONAccent") : Color(.systemGray5).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedPlan == .monthly ? Color("EEONAccent") : Color(.systemGray4), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Purchase CTA
                    Button {
                        isPurchasing = true
                        Task {
                            // Load products if needed
                            if subscriptionManager.products.isEmpty {
                                await subscriptionManager.loadProducts()
                            }
                            // Find the matching StoreKit Product
                            if let product = subscriptionManager.products.first(where: { $0.id == selectedPlan.rawValue }) {
                                do {
                                    let _ = try await subscriptionManager.purchase(product)
                                    await MainActor.run {
                                        isPurchasing = false
                                        OnboardingState.set(.completed)
                                    }
                                } catch {
                                    await MainActor.run {
                                        isPurchasing = false
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            } else {
                                await MainActor.run {
                                    isPurchasing = false
                                    errorMessage = "Could not load subscription. Try again."
                                    showError = true
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Subscribe & Get Started")
                                    .font(.body.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color("EEONAccent"))
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isPurchasing)

                    // Skip — try free
                    Button {
                        OnboardingState.set(.completed)
                    } label: {
                        Text("Try 5 free notes first")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color("EEONTextSecondary"))
                            .underline()
                    }
                    .padding(.top, 2)

                    // Legal links
                    HStack(spacing: 4) {
                        Link("Terms of use", destination: URL(string: "https://eeon.com/terms")!)
                        Text("|")
                        Link("Privacy policy", destination: URL(string: "https://eeon.com/privacy")!)
                    }
                    .font(.caption)
                    .foregroundStyle(Color("EEONTextPrimary").opacity(0.35))
                    .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }

    // MARK: - Sign in with Apple

    private func triggerSignInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = SignInDelegate { result in
            switch result {
            case .success(let authorization):
                authService.handleSignInResult(.success(authorization))
                if authService.isSignedIn {
                    OnboardingState.set(.completed)
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        // Store delegate to keep it alive
        SignInDelegate.current = delegate
        controller.delegate = delegate
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            let contextProvider = SignInPresentationContext(window: window)
            controller.presentationContextProvider = contextProvider
            SignInPresentationContext.current = contextProvider
        }
        controller.performRequests()
    }
}

// MARK: - Sign In Helpers

private class SignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    static var current: SignInDelegate?
    let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
        SignInDelegate.current = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
        SignInDelegate.current = nil
    }
}

private class SignInPresentationContext: NSObject, ASAuthorizationControllerPresentationContextProviding {
    static var current: SignInPresentationContext?
    let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }
}

#Preview {
    OnboardingPaywallView()
}
