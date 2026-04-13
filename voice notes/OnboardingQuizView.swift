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

// MARK: - Quiz Data

private enum UserRole: String, CaseIterable {
    case professional = "Working professional"
    case student = "Student"
    case creator = "Creator"
    case founder = "Founder / entrepreneur"
    case other = "Something else"

    var emoji: String {
        switch self {
        case .professional: return "💼"
        case .student: return "📚"
        case .creator: return "🎨"
        case .founder: return "🚀"
        case .other: return "🔧"
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
        case .captureIdeas: return "🎙"
        case .meetings: return "📋"
        case .secondBrain: return "🧠"
        case .thinkOutLoud: return "✍️"
        case .other: return "🔍"
        }
    }
}

// MARK: - OnboardingQuizView

struct OnboardingQuizView: View {
    @State private var currentStep = 0
    @State private var selectedRole: UserRole?
    @State private var selectedIntent: UserIntent?
    @State private var selectedPlan: SubscriptionProduct = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let subscriptionManager = SubscriptionManager.shared
    private let totalSteps = 6

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
                    socialProofScreen.tag(3)
                    featureScreen.tag(4)
                    paywallScreen.tag(5)
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
        VStack(spacing: 0) {
            Spacer()

            // App icon placeholder — use the app's accent color circle with mic
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color("EEONAccent"))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 24)

            Text("Your AI memory for\neverything you say")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color("EEONTextPrimary"))
                .padding(.bottom, 12)

            Text("try for $0")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color("EEONAccent"))
                .padding(.bottom, 8)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation { currentStep = 1 }
                } label: {
                    Text("Continue")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color("EEONTextPrimary"))
                        .foregroundStyle(Color("EEONBackground"))
                        .cornerRadius(14)
                }

                Button {
                    OnboardingState.set(.completed)
                } label: {
                    Text("Already have an account?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Screen 2: Role

    private var roleScreen: some View {
        quizScreen(
            header: "Personalizing your EEON...",
            question: "Which best describes you?"
        ) {
            ForEach(UserRole.allCases, id: \.self) { role in
                quizOption(
                    emoji: role.emoji,
                    title: role.rawValue,
                    subtitle: role.subtitle,
                    isSelected: selectedRole == role,
                    action: {
                        selectedRole = role
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { currentStep = 2 }
                        }
                    }
                )
            }
        }
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

    private var socialProofScreen: some View {
        let role = selectedRole ?? .other

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 24)

                    Text("You're in good company!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))

                    // Testimonial card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(role.testimonial)
                            .font(.body)
                            .foregroundStyle(Color("EEONTextPrimary"))
                            .italic()

                        HStack(spacing: 2) {
                            ForEach(0..<5) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                        }

                        Text("— \(role.personaName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Use cases
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(role.useCases, id: \.self) { useCase in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                                Text(useCase)
                                    .font(.body)
                                    .foregroundStyle(Color("EEONTextPrimary"))
                            }
                        }
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

    // MARK: - Screen 5: Features

    private var featureScreen: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 24)

                    Text("What EEON does for you")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("EEONTextPrimary"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        featureCard(emoji: "🎙", title: "Voice capture", subtitle: "Talk, we handle the rest")
                        featureCard(emoji: "🧠", title: "AI memory", subtitle: "Search everything you've said")
                        featureCard(emoji: "⚡", title: "Instant extraction", subtitle: "Decisions, actions, commitments")
                        featureCard(emoji: "✨", title: "Enhanced notes", subtitle: "Your words, polished")
                        featureCard(emoji: "🔗", title: "Multi-source", subtitle: "Add links, PDFs, files")
                        featureCard(emoji: "💬", title: "Ask anything", subtitle: "Query your entire memory")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }

            continueButton { withAnimation { currentStep = 5 } }
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

                    // Purchase CTA
                    Button {
                        purchaseSubscription()
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Start my FREE week")
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

                    // Skip
                    Button {
                        OnboardingState.set(.completed)
                    } label: {
                        Text("Start free with 5 notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Legal
                    Text("Terms of Service • Privacy Policy • Restore Purchases")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    private func quizOption(emoji: String, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color("EEONTextPrimary"))
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

    private func featureCard(emoji: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 32))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("EEONTextPrimary"))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
