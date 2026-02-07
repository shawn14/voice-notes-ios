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
            // Clean dark background
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 40)

                    // App icon / branding
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.black)
                        }

                        Text("Voice Notes")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    // Value proposition
                    VStack(spacing: 24) {
                        Text("Your thoughts, organized")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        VStack(alignment: .leading, spacing: 16) {
                            FeatureItem(icon: "waveform", text: "Unlimited voice notes")
                            FeatureItem(icon: "sparkles", text: "AI extracts decisions & action items")
                            FeatureItem(icon: "person.2", text: "Track commitments by person")
                            FeatureItem(icon: "icloud", text: "Sync across all your devices")
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(.horizontal)

                    // Subscription options
                    subscriptionSection
                        .padding(.horizontal)

                    // CTA buttons
                    ctaSection
                        .padding(.horizontal)

                    // Legal
                    legalSection

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

    // MARK: - Feature Item

    private struct FeatureItem: View {
        let icon: String
        let text: String

        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 24)

                Text(text)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()
            }
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
                VStack(spacing: 12) {
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
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Continue")
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .foregroundStyle(.black)
                .cornerRadius(12)
            }
            .disabled(isPurchasing || subscriptionManager.products.isEmpty)

            // Skip button
            Button {
                onComplete()
            } label: {
                Text("Try 5 Free Notes First")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 12)
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
            .foregroundStyle(.gray)
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(spacing: 6) {
            Text("Cancel anytime. Payment charged to Apple ID.")
                .font(.caption2)
                .foregroundStyle(.gray)

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://eeon.com/terms")!)
                Link("Privacy", destination: URL(string: "https://eeon.com/privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(.gray)
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
                        .stroke(isSelected ? Color.white : Color.gray.opacity(0.5), lineWidth: 2)
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
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("/\(period)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingPaywallView(onComplete: {})
}
