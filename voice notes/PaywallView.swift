//
//  PaywallView.swift
//  voice notes
//
//  Consent-based upgrade prompt with StoreKit 2
//

import SwiftUI
import StoreKit

// MARK: - Paywall View

struct PaywallView: View {
    let onDismiss: () -> Void

    @State private var selectedProductID: String = SubscriptionProduct.annual.rawValue
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let subscriptionManager = SubscriptionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .padding(.top, 32)

                // Headline
                Text("You've used your 5 free notes")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                // Subhead
                Text("Upgrade to keep capturing your thoughts")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Value props
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "infinity", text: "Unlimited notes")
                    FeatureRow(icon: "brain.head.profile", text: "AI-powered extraction")
                    FeatureRow(icon: "folder.fill", text: "Project organization")
                    FeatureRow(icon: "icloud.fill", text: "Sync across devices")
                    FeatureRow(icon: "waveform", text: "Unlimited recording time")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                Spacer().frame(height: 8)

                // Plan selection from StoreKit
                if subscriptionManager.isLoading && subscriptionManager.products.isEmpty {
                    ProgressView("Loading plans...")
                        .padding()
                } else if subscriptionManager.products.isEmpty {
                    Text("Unable to load subscription options")
                        .foregroundStyle(.secondary)
                        .padding()

                    Button("Retry") {
                        Task {
                            await subscriptionManager.loadProducts()
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        // Annual plan (recommended)
                        if let annualProduct = subscriptionManager.annualProduct {
                            ProductOptionCard(
                                product: annualProduct,
                                isSelected: selectedProductID == annualProduct.id,
                                isAnnual: true,
                                monthlyProduct: subscriptionManager.monthlyProduct,
                                onSelect: { selectedProductID = annualProduct.id }
                            )
                        }

                        // Monthly plan
                        if let monthlyProduct = subscriptionManager.monthlyProduct {
                            ProductOptionCard(
                                product: monthlyProduct,
                                isSelected: selectedProductID == monthlyProduct.id,
                                isAnnual: false,
                                monthlyProduct: nil,
                                onSelect: { selectedProductID = monthlyProduct.id }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // CTA
                Button(action: handlePurchase) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(purchaseButtonText)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(isPurchasing || subscriptionManager.products.isEmpty)

                // Restore purchases
                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.isSubscribed {
                            onDismiss()
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.blue)

                // Dismiss - low friction
                Button("Maybe Later") {
                    UsageService.shared.hasShownPaywall = true
                    onDismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)

                // Legal text
                VStack(spacing: 8) {
                    Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        Text("By subscribing, you agree to our")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Link("Terms of Use", destination: URL(string: "https://eeon.com/terms")!)
                            .font(.caption2)
                        Text("and")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Link("Privacy Policy", destination: URL(string: "https://eeon.com/privacy")!)
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
        .onAppear {
            // Ensure products are loaded
            if subscriptionManager.products.isEmpty {
                Task {
                    await subscriptionManager.loadProducts()
                }
            }
        }
    }

    private var purchaseButtonText: String {
        guard let product = subscriptionManager.products.first(where: { $0.id == selectedProductID }) else {
            return "Subscribe"
        }
        return "Start Pro - \(product.displayPrice)/\(product.subscriptionPeriodText)"
    }

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
                        UsageService.shared.hasShownPaywall = true
                        onDismiss()
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

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

// MARK: - Product Option Card

struct ProductOptionCard: View {
    let product: Product
    let isSelected: Bool
    let isAnnual: Bool
    let monthlyProduct: Product?
    let onSelect: () -> Void

    private var savingsPercentage: Int? {
        guard isAnnual,
              let monthlyProduct = monthlyProduct,
              let annualMonthly = product.monthlyEquivalentPrice else {
            return nil
        }

        let monthlyPrice = monthlyProduct.price
        let savings = (1 - (annualMonthly / monthlyPrice)) * 100
        return Int(NSDecimalNumber(decimal: savings).doubleValue)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isAnnual ? "Annual" : "Monthly")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let savings = savingsPercentage, savings > 0 {
                            Text("Save \(savings)%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    if isAnnual, let monthlyEquiv = product.monthlyEquivalentPrice {
                        Text("\(monthlyEquiv.formatted(.currency(code: "USD")))/month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(product.displayPrice)/\(product.subscriptionPeriodText)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView(onDismiss: {})
}
