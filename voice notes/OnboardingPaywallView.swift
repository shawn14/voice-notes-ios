//
//  OnboardingPaywallView.swift
//  voice notes
//
//  Soft paywall shown during onboarding - users can subscribe immediately
//  or skip to try 5 free notes first
//

import SwiftUI
import StoreKit

struct OnboardingPaywallView: View {
    let onComplete: () -> Void

    @State private var selectedProductID: String = SubscriptionProduct.annual.rawValue
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let subscriptionManager = SubscriptionManager.shared

    var body: some View {
        ZStack {
            // Atmospheric background matching onboarding page 3
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [Color.blue.opacity(0.15), Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Headline — editorial, not template
                    VStack(spacing: 14) {
                        Text("Go unlimited.")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Everything you just saw,\nwithout limits.")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }

                    Spacer().frame(height: 36)

                    // Feature list — minimal, matching onboarding style
                    VStack(spacing: 16) {
                        paywallFeature("infinity", "Unlimited voice notes")
                        paywallFeature("sparkles", "AI extraction on every note")
                        paywallFeature("chart.bar.doc.horizontal", "CEO reports & SWOT analysis")
                        paywallFeature("person.2", "People & commitment tracking")
                        paywallFeature("arrow.trianglehead.2.clockwise", "Sync across all devices")
                    }
                    .padding(.horizontal, 40)

                    Spacer().frame(height: 36)

                    // Subscription options
                    subscriptionSection
                        .padding(.horizontal, 28)

                    Spacer().frame(height: 24)

                    // CTA
                    ctaSection
                        .padding(.horizontal, 28)

                    // Legal
                    legalSection
                        .padding(.top, 20)

                    Spacer().frame(height: 20)
                }
            }
        }
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
        .onAppear {
            if subscriptionManager.products.isEmpty {
                Task {
                    await subscriptionManager.loadProducts()
                }
            }
        }
    }

    // MARK: - Feature Row (matches onboarding style)

    private func paywallFeature(_ icon: String, _ text: String) -> some View {
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

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Group {
            if subscriptionManager.isLoading && subscriptionManager.products.isEmpty {
                ProgressView()
                    .tint(.white)
                    .padding(.vertical, 40)
            } else if subscriptionManager.products.isEmpty {
                VStack(spacing: 12) {
                    Text("Unable to load plans")
                        .foregroundStyle(.gray)
                    Button("Retry") {
                        Task {
                            await subscriptionManager.loadProducts()
                        }
                    }
                    .foregroundStyle(.blue)
                }
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    // Annual (recommended)
                    if let annual = subscriptionManager.annualProduct {
                        PlanOption(
                            title: "Annual",
                            price: annual.displayPrice,
                            period: "year",
                            subtitle: monthlyEquivalent(for: annual),
                            badge: savingsBadge(for: annual),
                            isSelected: selectedProductID == annual.id
                        ) {
                            selectedProductID = annual.id
                        }
                    }

                    // Monthly
                    if let monthly = subscriptionManager.monthlyProduct {
                        PlanOption(
                            title: "Monthly",
                            price: monthly.displayPrice,
                            period: "month",
                            subtitle: nil,
                            badge: nil,
                            isSelected: selectedProductID == monthly.id
                        ) {
                            selectedProductID = monthly.id
                        }
                    }
                }
            }
        }
    }

    private func monthlyEquivalent(for product: Product) -> String? {
        guard let monthly = product.monthlyEquivalentPrice else { return nil }
        return "\(monthly.formatted(.currency(code: "USD")))/month"
    }

    private func savingsBadge(for product: Product) -> String? {
        guard let monthlyProduct = subscriptionManager.monthlyProduct,
              let annualMonthly = product.monthlyEquivalentPrice else { return nil }
        let monthlyPrice = monthlyProduct.price
        let savings = (1 - (annualMonthly / monthlyPrice)) * 100
        let percent = Int(NSDecimalNumber(decimal: savings).doubleValue)
        return percent > 0 ? "Save \(percent)%" : nil
    }

    // MARK: - CTA Section

    private var ctaSection: some View {
        VStack(spacing: 14) {
            // Subscribe button
            Button(action: handlePurchase) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Start Pro")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .foregroundStyle(.black)
                .cornerRadius(14)
            }
            .disabled(isPurchasing || subscriptionManager.products.isEmpty)

            // Skip button
            Button {
                onComplete()
            } label: {
                Text("Try 5 free notes first")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Restore purchases
            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restorePurchases()
                    if subscriptionManager.isSubscribed {
                        onComplete()
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 4)
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: 6) {
            Text("Cancel anytime. Payment charged to Apple ID.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://eeon.com/terms")!)
                Link("Privacy", destination: URL(string: "https://eeon.com/privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.bottom, 16)
    }

    // MARK: - Purchase Handler

    private func handlePurchase() {
        guard let product = subscriptionManager.products.first(where: { $0.id == selectedProductID }) else {
            return
        }

        isPurchasing = true

        Task {
            do {
                let success = try await subscriptionManager.purchase(product)

                await MainActor.run {
                    isPurchasing = false
                    if success {
                        onComplete()
                    }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Plan Option

struct PlanOption: View {
    let title: String
    let price: String
    let period: String
    let subtitle: String?
    let badge: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)

                        if let badge = badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white)
                                .cornerRadius(4)
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("/\(period)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingPaywallView(onComplete: {})
}
