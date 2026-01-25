//
//  PaywallView.swift
//  voice notes
//
//  Consent-based upgrade prompt
//

import SwiftUI

// MARK: - Subscription Plan

enum SubscriptionPlan: String, CaseIterable {
    case monthly
    case annual

    var price: String {
        switch self {
        case .monthly: return "$9.99"
        case .annual: return "$79.99"
        }
    }

    var period: String {
        switch self {
        case .monthly: return "month"
        case .annual: return "year"
        }
    }

    var monthlyEquivalent: String? {
        switch self {
        case .monthly: return nil
        case .annual: return "$6.67/month"
        }
    }

    var savings: String? {
        switch self {
        case .monthly: return nil
        case .annual: return "Save 33%"
        }
    }
}

// MARK: - Paywall View

struct PaywallView: View {
    let onDismiss: () -> Void
    @State private var selectedPlan: SubscriptionPlan = .annual  // Default to annual (best value)
    @State private var isPurchasing = false

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

                // Plan selection
                VStack(spacing: 12) {
                    // Annual plan (recommended)
                    PlanOptionCard(
                        plan: .annual,
                        isSelected: selectedPlan == .annual,
                        onSelect: { selectedPlan = .annual }
                    )

                    // Monthly plan
                    PlanOptionCard(
                        plan: .monthly,
                        isSelected: selectedPlan == .monthly,
                        onSelect: { selectedPlan = .monthly }
                    )
                }
                .padding(.horizontal)

                // CTA
                Button(action: handlePurchase) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start Pro - \(selectedPlan.price)/\(selectedPlan.period)")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(isPurchasing)

                // Dismiss - low friction
                Button("Maybe Later") {
                    UsageService.shared.hasShownPaywall = true
                    onDismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
            }
        }
    }

    private func handlePurchase() {
        isPurchasing = true

        // TODO: Implement StoreKit purchase for selectedPlan
        // For now, simulate a brief delay then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isPurchasing = false
            // In real implementation, check if purchase succeeded
            // UsageService.shared.upgradeToPro()
            UsageService.shared.hasShownPaywall = true
            onDismiss()
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

// MARK: - Plan Option Card

struct PlanOptionCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan == .annual ? "Annual" : "Monthly")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let savings = plan.savings {
                            Text(savings)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    if let equivalent = plan.monthlyEquivalent {
                        Text(equivalent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(plan.price)/\(plan.period)")
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
