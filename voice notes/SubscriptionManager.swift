//
//  SubscriptionManager.swift
//  voice notes
//
//  Handles StoreKit 2 subscriptions
//

import Foundation
import StoreKit

// MARK: - Product IDs

enum SubscriptionProduct: String, CaseIterable {
    case monthly = "pro_monthly"
    case annual = "pro_annual"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }
}

// MARK: - Subscription Manager

@Observable
class SubscriptionManager {
    static let shared = SubscriptionManager()

    // Products
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    // State
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Transaction listener task
    private var updateListenerTask: Task<Void, Error>?

    init() {
        // Start listening for transactions
        updateListenerTask = listenForTransactions()

        // Load products and check subscription status on init
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Computed Properties

    var isSubscribed: Bool {
        !purchasedProductIDs.isEmpty
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProduct.monthly.rawValue }
    }

    var annualProduct: Product? {
        products.first { $0.id == SubscriptionProduct.annual.rawValue }
    }

    // MARK: - Load Products

    @MainActor
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let productIDs = SubscriptionProduct.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)

            // Sort so annual comes first (better value)
            products.sort { $0.id == SubscriptionProduct.annual.rawValue && $1.id != SubscriptionProduct.annual.rawValue }

        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("StoreKit error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // Check if the transaction is verified
            let transaction = try checkVerified(verification)

            // Update subscription status
            await updateSubscriptionStatus()

            // Always finish the transaction
            await transaction.finish()

            return true

        case .userCancelled:
            return false

        case .pending:
            // Transaction is pending (e.g., Ask to Buy)
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore Purchases

    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // This syncs with the App Store
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    // MARK: - Update Subscription Status

    @MainActor
    func updateSubscriptionStatus() async {
        var purchasedIDs: Set<String> = []

        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // Check if it's one of our subscription products
                if SubscriptionProduct.allCases.map({ $0.rawValue }).contains(transaction.productID) {
                    purchasedIDs.insert(transaction.productID)
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }

        self.purchasedProductIDs = purchasedIDs

        // Update UsageService
        if isSubscribed {
            UsageService.shared.upgradeToPro()
        } else {
            UsageService.shared.downgradeToFree()
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Update subscription status
                    await self.updateSubscriptionStatus()

                    // Always finish transactions
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }

    // MARK: - Verification Helper

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Store Errors

enum StoreError: Error {
    case failedVerification
}

// MARK: - Product Extensions

extension Product {
    var subscriptionPeriodText: String {
        guard let subscription = self.subscription else { return "" }

        let unit = subscription.subscriptionPeriod.unit
        let value = subscription.subscriptionPeriod.value

        switch unit {
        case .day:
            return value == 1 ? "day" : "\(value) days"
        case .week:
            return value == 1 ? "week" : "\(value) weeks"
        case .month:
            return value == 1 ? "month" : "\(value) months"
        case .year:
            return value == 1 ? "year" : "\(value) years"
        @unknown default:
            return ""
        }
    }

    var monthlyEquivalentPrice: Decimal? {
        guard let subscription = self.subscription else { return nil }

        let period = subscription.subscriptionPeriod

        switch period.unit {
        case .year:
            return price / Decimal(12 * period.value)
        case .month:
            return price / Decimal(period.value)
        default:
            return nil
        }
    }
}
