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

    @State private var selectedProductID: String = SubscriptionProduct.annual.rawValue
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let subscriptionManager = SubscriptionManager.shared

    var body: some View {
        ZStack {
            // Rich layered atmospheric background
            Color("EEONBackground").ignoresSafeArea()

            RadialGradient(
                colors: [Color("EEONAccent").opacity(0.2), Color("EEONAccent").opacity(0.04), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 500
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.indigo.opacity(0.08), Color.clear],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 350
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 50)

                    // Pro badge icon
                    ZStack {
                        Circle()
                            .fill(Color("EEONTextPrimary").opacity(0.04))
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(Color("EEONTextPrimary").opacity(0.06))
                            .frame(width: 56, height: 56)

                        Image(systemName: "crown.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color("EEONAccent"), Color("EEONAccent").opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .padding(.bottom, 24)

                    // Headline
                    VStack(spacing: 12) {
                        Text("Go unlimited.")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Color("EEONTextPrimary"))
                            .tracking(-0.5)

                        Text("Everything you just saw,\nwithout limits.")
                            .font(.system(size: 17))
                            .foregroundStyle(Color("EEONTextSecondary"))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }

                    Spacer().frame(height: 32)

                    // Feature list — glass-backed card
                    VStack(spacing: 14) {
                        paywallFeature("infinity", "Unlimited voice notes")
                        paywallFeature("sparkles", "AI extraction on every note")
                        paywallFeature("chart.bar.doc.horizontal", "CEO reports & SWOT analysis")
                        paywallFeature("person.2", "People & commitment tracking")
                        paywallFeature("arrow.trianglehead.2.clockwise", "Sync across all devices")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color("EEONCardBackground").opacity(0.6))
                    )
                    .padding(.horizontal, 28)

                    Spacer().frame(height: 28)

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
        .task {
            // Auto-check subscription status — skip paywall if already subscribed
            await subscriptionManager.updateSubscriptionStatus()
            if subscriptionManager.isSubscribed {
                OnboardingState.set(.completed)
                return
            }

            // Load products if needed
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
        }
    }

    // MARK: - Feature Row (matches onboarding style)

    private func paywallFeature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color("EEONTextSecondary"))
                .frame(width: 24, height: 24)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color("EEONTextPrimary").opacity(0.8))

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
                        .foregroundStyle(Color("EEONTextSecondary"))
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
        VStack(spacing: 16) {
            // Subscribe button
            Button(action: handlePurchase) {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start Pro")
                            .font(.body.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color("EEONAccent"))
                .foregroundStyle(.white)
                .cornerRadius(14)
            }
            .disabled(isPurchasing || subscriptionManager.products.isEmpty)
            .opacity(subscriptionManager.products.isEmpty ? 0.5 : 1)

            // Skip button
            Button {
                OnboardingState.set(.completed)
            } label: {
                Text("Try 10 free notes first")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color("EEONTextSecondary"))
                    .underline()
            }

            // Restore purchases
            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restorePurchases()
                    if subscriptionManager.isSubscribed {
                        OnboardingState.set(.completed)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Color("EEONTextSecondary").opacity(0.6))
            .padding(.top, 2)
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: 6) {
            Text("Cancel anytime. Payment charged to Apple ID.")
                .font(.caption2)
                .foregroundStyle(Color("EEONTextSecondary").opacity(0.5))

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://eeon.com/terms")!)
                Link("Privacy", destination: URL(string: "https://eeon.com/privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(Color("EEONTextSecondary").opacity(0.5))
        }
        .padding(.bottom, 16)
    }

    // MARK: - Purchase Handler

    private func handlePurchase() {
        print("StoreKit: handlePurchase called. selectedProductID=\(selectedProductID), products=\(subscriptionManager.products.map { $0.id })")
        guard let product = subscriptionManager.products.first(where: { $0.id == selectedProductID }) else {
            print("StoreKit: No product found for \(selectedProductID)!")
            errorMessage = "Product not available. Please try again."
            showError = true
            return
        }

        isPurchasing = true

        Task {
            do {
                let success = try await subscriptionManager.purchase(product)

                await MainActor.run {
                    isPurchasing = false
                    if success {
                        OnboardingState.set(.completed)
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
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color("EEONAccent") : Color("EEONTextSecondary").opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color("EEONAccent"))
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color("EEONTextPrimary"))

                        if let badge = badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color("EEONAccent"))
                                )
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color("EEONTextSecondary"))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color("EEONTextPrimary"))
                    Text("/\(period)")
                        .font(.caption)
                        .foregroundStyle(Color("EEONTextSecondary"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("EEONCardBackground").opacity(isSelected ? 0.8 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color("EEONAccent").opacity(0.5) : Color("EEONDivider").opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    OnboardingPaywallView()
}
