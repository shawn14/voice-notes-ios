//
//  UsageExplainerView.swift
//  voice notes
//
//  "Why am I seeing this?" sheet explaining free tier limits
//

import SwiftUI

struct UsageExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Brain icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.top, 8)

            // Headline
            Text("Why am I seeing this?")
                .font(.title3.weight(.bold))

            // Explanation
            VStack(spacing: 12) {
                Text("Recording is free and unlimited.")
                    .font(.body)
                    .foregroundStyle(.primary)

                Text("AI understanding costs compute, so we limit free extractions to help keep the lights on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            // Current limits
            VStack(spacing: 8) {
                LimitRow(
                    icon: "mic.fill",
                    label: "Recording",
                    value: "Unlimited",
                    valueColor: .green
                )

                LimitRow(
                    icon: "brain.head.profile",
                    label: "AI Extractions",
                    value: "5 free",
                    valueColor: .orange
                )

                LimitRow(
                    icon: "checkmark.circle.fill",
                    label: "Resolutions",
                    value: "3 free",
                    valueColor: .orange
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Pro removes limits
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Pro removes all limits")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 4)

            Spacer()

            // Dismiss button
            Button(action: { dismiss() }) {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding(24)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Limit Row

struct LimitRow: View {
    let icon: String
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }
}

#Preview {
    Text("Background")
        .sheet(isPresented: .constant(true)) {
            UsageExplainerView()
        }
}
