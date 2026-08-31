//
//  OnboardingQuizView.swift
//  voice notes
//
//  6-screen progressive profiling onboarding quiz.
//  Screens: Hero → Role → Intent → Social Proof → Features → Paywall
//  Answers are used for in-session social proof only (not persisted).
//

import SwiftUI
import StoreKit
import AuthenticationServices

// MARK: - Quiz Data

private enum UserRole: String, CaseIterable {
    case professional = "Working professional"
    case student = "Student"
    case creator = "Creator"
    case founder = "Founder / entrepreneur"
    case other = "Something else"

    var emoji: String {
        switch self {
        case .professional: return "briefcase"
        case .student: return "graduationcap"
        case .creator: return "paintbrush"
        case .founder: return "hammer"
        case .other: return "person"
        }
    }

    var subtitle: String {
        switch self {
        case .professional: return "Meetings, ideas, decisions"
        case .student: return "Lectures, study notes, research"
        case .creator: return "Ideas, scripts, content planning"
        case .founder: return "Strategy, pitches, team notes"
        case .other: return ""
        }
    }

    var testimonial: String {
        switch self {
        case .professional:
            return "EEON has helped me stop losing action items from meetings. I just talk, and everything is organized."
        case .student:
            return "I record lectures and EEON extracts all the key concepts. It's like having a study partner."
        case .creator:
            return "I dump ideas all day and EEON turns them into structured notes I can actually use."
        case .founder:
            return "Every decision, every commitment — it's all captured and searchable. Game changer."
        case .other:
            return "I never realized how much I was forgetting until EEON started remembering for me."
        }
    }

    var personaName: String {
        switch self {
        case .professional: return "Sarah M., Product Manager"
        case .student: return "Alex K., Graduate Student"
        case .creator: return "Jordan L., Content Creator"
        case .founder: return "Mike R., Startup Founder"
        case .other: return "Taylor S., EEON User"
        }
    }

    var useCases: [String] {
        switch self {
        case .professional: return ["Capture meeting action items", "Search past decisions", "Never miss a follow-up"]
        case .student: return ["Record and review lectures", "Extract key concepts", "Build study notes automatically"]
        case .creator: return ["Capture ideas on the go", "Turn voice into polished drafts", "Organize creative projects"]
        case .founder: return ["Track every decision", "Capture investor call notes", "Search your entire history"]
        case .other: return ["Voice-first note capture", "AI-powered organization", "Searchable memory"]
        }
    }
}

private enum UserIntent: String, CaseIterable {
    case captureIdeas = "Capture ideas on the go"
    case meetings = "Never forget what was said in meetings"
    case secondBrain = "Build a searchable second brain"
    case thinkOutLoud = "Think out loud, get organized text back"
    case other = "Something else"

    var emoji: String {
        switch self {
        case .captureIdeas: return "waveform"
        case .meetings: return "person.3"
        case .secondBrain: return "brain"
        case .thinkOutLoud: return "bubble.left.and.bubble.right"
        case .other: return "magnifyingglass"
        }
    }
}

// MARK: - OnboardingQuizView

struct OnboardingQuizView: View {
    @State private var currentStep = 0
    @State private var selectedPresetId: String?
    @State private var selectedRole: UserRole?
    @State private var selectedIntent: UserIntent?
    @State private var selectedPlan: SubscriptionProduct = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    @Environment(\.openURL) private var openURL

    private let subscriptionManager = SubscriptionManager.shared
    private let authService = AuthService.shared
    private let totalSteps = 5

    private let termsURL = URL(string: "https://eeon.com/terms")!
    private let privacyURL = URL(string: "https://eeon.com/privacy")!

    var body: some View {
        ZStack {
            Color("EEONBackground").ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (hidden on hero screen)
                if currentStep > 0 {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                // Screen content
                TabView(selection: $currentStep) {
                    heroScreen.tag(0)
                    roleScreen.tag(1)
                    intentScreen.tag(2)
                    // socialProofScreen removed 2026-08-20 — it showed
                    // testimonials from invented people. Fabricated social
                    // proof doesn't ship.
                    featureScreen.tag(3)
                    paywallScreen.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color("EEONAccent"))
                    .frame(width: geo.size.width * CGFloat(currentStep) / CGFloat(totalSteps - 1), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Screen 1: Hero

    private var heroScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.eeonAccent)
                    .frame(width: 72, height: 72)
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, EEONLayout.loose)

            Text("Welcome to EEON")
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextSecondary)
                .padding(.bottom, EEONLayout.tight)

            Text("Your personal\nAI assistant.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, EEONLayout.snug)

            Text("Use the phone in your pocket. Talk naturally; EEON remembers, organizes, and follows up.")
                .font(EEONType.body)
                .foregroundStyle(.eeonTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: EEONLayout.snug) {
                Button {
                    withAnimation { currentStep = 1 }
                } label: {
                    Text("Get started")
                        .font(EEONType.control)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(Color.eeonTextPrimary)
                        .foregroundStyle(Color.eeonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                appleSignInButton {
                    OnboardingState.set(.completed)
                }
            }
        }
        .padding(.horizontal, EEONLayout.loose)
        .padding(.bottom, EEONLayout.loose)
    }

    // MARK: - Screen 2: Role

    private var roleScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("So EEON knows your world")
                .font(EEONType.meta)
                .foregroundStyle(.eeonTextSecondary)
                .padding(.bottom, EEONLayout.tight)

            Text("What do you do?")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, EEONLayout.snug)

            Text("This shapes what EEON pulls from your notes and how it writes them. You can change it any time.")
                .font(EEONType.preview)
                .foregroundStyle(.eeonTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, EEONLayout.standard)

            ScrollView(showsIndicators: false) {
                VStack(spacing: EEONLayout.tight) {
                    // The same presets Tune EEON uses — one system, not a
                    // parallel role list that drifts from it.
                    ForEach(PersonaPresetCatalog.all) { preset in
                        presetOnboardingRow(preset)
                    }
                }
            }
        }
        .padding(.horizontal, EEONLayout.loose)
        .padding(.top, EEONLayout.standard)
        .padding(.bottom, EEONLayout.snug)
    }

    private func presetOnboardingRow(_ preset: PersonaPreset) -> some View {
        Button {
            PersonaPresetStore.apply(preset)
            selectedPresetId = preset.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation { currentStep = 2 }
            }
        } label: {
            HStack(spacing: EEONLayout.snug) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundStyle(selectedPresetId == preset.id ? Color.white : Color.eeonAccent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(EEONType.body)
                        .foregroundStyle(selectedPresetId == preset.id ? Color.white : Color.eeonTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(preset.blurb)
                        .font(EEONType.meta)
                        .foregroundStyle(selectedPresetId == preset.id ? Color.white.opacity(0.85) : Color.eeonTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: EEONLayout.tight)
            }
            .padding(.horizontal, EEONLayout.standard)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedPresetId == preset.id ? Color.eeonAccent : Color.eeonCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen 3: Intent

    private var intentScreen: some View {
        quizScreen(
            header: "Personalizing your EEON...",
            question: "What brings you to EEON?"
        ) {
            ForEach(UserIntent.allCases, id: \.self) { intent in
                quizOption(
                    emoji: intent.emoji,
                    title: intent.rawValue,
                    subtitle: nil,
                    isSelected: selectedIntent == intent,
                    action: {
                        selectedIntent = intent
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { currentStep = 3 }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Screen 4: Social Proof

    private var featureScreen: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 24)

                    Text("What EEON does for you")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        featureCard(emoji: "waveform", title: "Voice capture", subtitle: "Talk, we handle the rest")
                        featureCard(emoji: "brain", title: "AI memory", subtitle: "Search everything you've said")
                        featureCard(emoji: "bolt", title: "Instant extraction", subtitle: "Decisions, actions, commitments")
                        featureCard(emoji: "sparkles", title: "Enhanced notes", subtitle: "Your words, polished")
                        featureCard(emoji: "link", title: "Multi-source", subtitle: "Add links, PDFs, files")
                        featureCard(emoji: "bubble.left", title: "Ask anything", subtitle: "Query your entire memory")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            continueButton { withAnimation { currentStep = 4 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 6: Paywall

    private var paywallScreen: some View {
        VStack(spacing: 0) {
            // Close/skip button
            HStack {
                Spacer()
                Button {
                    OnboardingState.set(.completed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Text("Start capturing\nwith EEON")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color("EEONTextPrimary"))
                        .padding(.top, 8)

                    // Feature comparison
                    featureComparisonTable

                    // Plan selector
                    HStack(spacing: 12) {
                        planButton(plan: .annual, label: "Annual", price: "$79.99/yr", perMonth: "$6.67/mo")
                        planButton(plan: .monthly, label: "Monthly", price: "$9.99/mo", perMonth: nil)
                    }

                    // Sign In with Apple — primary CTA
                    appleSignInButton {
                        purchaseSubscription()
                    }

                    if isPurchasing {
                        ProgressView("Setting up your account...")
                            .tint(Color("EEONAccent"))
                    }

                    // Skip — try free without sign-in
                    Button {
                        OnboardingState.set(.completed)
                    } label: {
                        Text("Try 5 free notes first")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Legal — Button + openURL so taps reliably fire on Mac
                    // Catalyst (Apple Review 3.1.2(c)). Underlined .primary so
                    // links stay legible on light + dark backgrounds.
                    // Restore Purchases is wired to SubscriptionManager so it
                    // also satisfies Apple Review Guideline 3.1.1.
                    HStack(spacing: 12) {
                        Button {
                            openURL(termsURL)
                        } label: {
                            Text("Terms of Service")
                                .font(.caption2.weight(.semibold))
                                .underline()
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Terms of Service")

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            openURL(privacyURL)
                        } label: {
                            Text("Privacy Policy")
                                .font(.caption2.weight(.semibold))
                                .underline()
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Privacy Policy")

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await subscriptionManager.restorePurchases()
                                if subscriptionManager.isSubscribed {
                                    OnboardingState.set(.completed)
                                }
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.caption2.weight(.semibold))
                                .underline()
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Restore Purchases")
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Paywall Helpers

    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.caption.weight(.semibold))
                    .frame(width: 50)
                Text("Pro")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color("EEONAccent"))
                    .frame(width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            let features: [(String, Bool, Bool)] = [
                ("Voice capture", true, true),
                ("AI extraction", true, true),
                ("5 free notes", true, true),
                ("Unlimited notes", false, true),
                ("Multi-source ingest", false, true),
                ("AI memory search", false, true),
                ("Post-capture transforms", false, true),
            ]

            ForEach(features, id: \.0) { feature, free, pro in
                HStack {
                    Text(feature)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    featureCheck(enabled: free)
                        .frame(width: 50)
                    featureCheck(enabled: pro)
                        .frame(width: 50)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureCheck(enabled: Bool) -> some View {
        Image(systemName: enabled ? "checkmark.circle.fill" : "minus")
            .font(.subheadline)
            .foregroundStyle(enabled ? Color("EEONAccent") : .secondary)
    }

    private func planButton(plan: SubscriptionProduct, label: String, price: String, perMonth: String?) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(price)
                    .font(.caption.weight(.medium))
                if let perMonth = perMonth {
                    Text(perMonth)
                        .font(.caption2)
                        .foregroundStyle(selectedPlan == plan ? .white.opacity(0.7) : .secondary)
                }
            }
            .foregroundStyle(selectedPlan == plan ? .white : Color("EEONTextPrimary"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedPlan == plan ? Color("EEONAccent") : Color(.systemGray5).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedPlan == plan ? Color("EEONAccent") : Color(.systemGray4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func purchaseSubscription() {
        isPurchasing = true
        Task {
            // Check if already subscribed (e.g. restored purchase)
            await subscriptionManager.updateSubscriptionStatus()
            if subscriptionManager.isSubscribed {
                await MainActor.run {
                    isPurchasing = false
                    OnboardingState.set(.completed)
                }
                return
            }

            // Try to purchase selected plan
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
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
                        // Sign-in succeeded even if purchase was cancelled — go to app
                        OnboardingState.set(.completed)
                    }
                }
            } else {
                await MainActor.run {
                    isPurchasing = false
                    // Products couldn't load — still let them into the app
                    OnboardingState.set(.completed)
                }
            }
        }
    }

    private func appleSignInButton(onSuccess: @escaping () -> Void) -> some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignInCompletion(result, onSuccess: onSuccess)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 54)
        .cornerRadius(14)
    }

    private func handleAppleSignInCompletion(
        _ result: Result<ASAuthorization, Error>,
        onSuccess: () -> Void
    ) {
        switch result {
        case .success(let authorization):
            authService.handleSignInResult(.success(authorization))
            if authService.isSignedIn {
                onSuccess()
            }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Reusable Components

    private func quizScreen<Content: View>(header: String, question: String, @ViewBuilder options: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer().frame(height: 16)

                    Text(header)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color("EEONAccent"))

                    Text(question)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))
                        .padding(.bottom, 8)

                    options()
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func quizOption(emoji symbol: String, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.eeonAccent)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("EEONTextPrimary"))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color("EEONAccent"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color("EEONAccent").opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color("EEONAccent").opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func featureCard(emoji symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.eeonAccent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("EEONTextPrimary"))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("Continue")
                    .font(.body.weight(.bold))
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color("EEONTextPrimary"))
            .foregroundStyle(Color("EEONBackground"))
            .cornerRadius(14)
        }
    }
}
