import Foundation
import StoreKit
import SwiftData

// MARK: - Transaction finish deduplication

/// `purchase()` と `Transaction.updates` の両方で同一トランザクションが届くため、`finish()` は一度だけにする。
private actor TransactionFinishTracker {
    private var finishedIDs = Set<UInt64>()

    func finishOnce(_ transaction: Transaction) async {
        let id = transaction.id
        guard !finishedIDs.contains(id) else { return }
        finishedIDs.insert(id)
        await transaction.finish()
    }
}

// MARK: - AppPlan

enum AppPlan: String {
    case free = "free"
    case paid = "paid"

    var displayName: String {
        switch self {
        case .free: "FREE"
        case .paid: "PREMIUM"
        }
    }
}

// MARK: - PurchaseError

enum PurchaseError: LocalizedError {
    case productNotFound
    case verificationFailed(String)

    var errorDescription: String? {
        let s = LocalizedStrings.current
        switch self {
        case .productNotFound:
            return s.purchaseProductNotFound
        case .verificationFailed(let details):
            return s.purchaseVerificationFailed(details)
        }
    }
}

// MARK: - PlanLimitExceededError

enum PlanLimitExceededError: LocalizedError {
    case showRegistration
    case folderCreation

    var errorDescription: String? {
        let lang = LocalizedStrings.current
        switch self {
        case .showRegistration:
            return lang.showRegistrationLimitReached
        case .folderCreation:
            return lang.folderCreationLimitReached
        }
    }
}

// MARK: - PlanStore

@Observable
final class PlanStore: @unchecked Sendable {
    static let shared = PlanStore()

    static let productID = "com.osamushikubo.osmPod.upgrade"
    static let freeShowLimit = 3
    static let freeFolderLimit = 5

    private static let storageKey = "osmPod_plan"

    private let transactionFinishTracker = TransactionFinishTracker()

    private(set) var currentPlan: AppPlan {
        didSet {
            guard oldValue != currentPlan else { return }
            save()
        }
    }

    var isPaid: Bool { currentPlan == .paid }
    var isFree: Bool { currentPlan == .free }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let plan = AppPlan(rawValue: raw) {
            currentPlan = plan
        } else {
            currentPlan = .free
        }
    }

    func setPlan(_ plan: AppPlan) {
        currentPlan = plan
    }

    /// FREE のとき、これから番組を1件追加できるか（現在の件数ベース）。
    func canRegisterAnotherShow(context: ModelContext) -> Bool {
        guard !isPaid else { return true }
        let n = (try? context.fetchCount(FetchDescriptor<Show>())) ?? 0
        return n < Self.freeShowLimit
    }

    /// FREE のとき、これからフォルダを1つ追加できるか。
    func canCreateAnotherFolder(context: ModelContext) -> Bool {
        guard !isPaid else { return true }
        let n = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        return n < Self.freeFolderLimit
    }

    func validateCanRegisterShow(context: ModelContext) throws {
        guard !canRegisterAnotherShow(context: context) else { return }
        throw PlanLimitExceededError.showRegistration
    }

    func validateCanCreateFolder(context: ModelContext) throws {
        guard !canCreateAnotherFolder(context: context) else { return }
        throw PlanLimitExceededError.folderCreation
    }

    // MARK: - StoreKit

    /// StoreKit が要求する「起動時から `Transaction.updates` を iterate する Task」。SwiftUI の `.task` から呼ぶ。
    /// （`init` 内の `Task {}` ではランタイム検知が追いつかず購入時警告が出ることがある。）
    @MainActor
    func listenForTransactionUpdatesForever() async {
        Self.log("Transaction.updates: listener loop starting")
        for await verificationResult in Transaction.updates {
            await handleTransactionUpdate(verificationResult)
        }
    }

    /// App Store 側の権利とローカル表示を一致させる（起動時・購入前・復元後）。
    /// `currentEntitlements` は現在有効な権利しか列挙しないため、返金・失効などで
    /// 対象 productID が見つからなかった場合は明示的に `.free` へ戻す
    /// （そうしないと一度 `.paid` になった端末は権利消失後も無制限のまま残ってしまう）。
    @MainActor
    func syncPlanWithStore() async {
        var foundActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == Self.productID else { continue }
                Self.log("entitlements: active productID=\(transaction.productID), transactionID=\(transaction.id)")
                foundActiveEntitlement = true
                setPlan(.paid)
            case .unverified(let transaction, let error):
                Self.log("entitlements: unverified productID=\(transaction.productID), \(error.localizedDescription)")
            }
        }
        if !foundActiveEntitlement, isPaid {
            Self.log("entitlements: no active entitlement found for productID=\(Self.productID) -> downgrading to .free")
            setPlan(.free)
        }
    }

    @MainActor
    private func handleTransactionUpdate(_ verificationResult: VerificationResult<Transaction>) async {
        switch verificationResult {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else { return }
            Self.log("Transaction.updates: verified id=\(transaction.id), productID=\(transaction.productID)")
            await transactionFinishTracker.finishOnce(transaction)
            Self.log("Transaction.updates: finish processed id=\(transaction.id)")
            setPlan(.paid)
        case .unverified(let transaction, let error):
            Self.log("Transaction.updates: unverified id=\(transaction.id), productID=\(transaction.productID), \(error.localizedDescription)")
        }
    }

    private static func log(_ message: String) {
        print("[IAP] \(message)")
    }

    static func storeEnvironmentSummary() -> String {
        let receiptName = Bundle.main.appStoreReceiptURL?.lastPathComponent ?? "none"
        let storekitInBundle = Bundle.main.path(forResource: "osmPod", ofType: "storekit") != nil
        if receiptName == "sandboxReceipt" {
            return "sandbox(App Store Connect test), receipt=\(receiptName), bundledStoreKitFile=\(storekitInBundle)"
        }
        return "production/local-config, receipt=\(receiptName), bundledStoreKitFile=\(storekitInBundle)"
    }

    @MainActor
    func purchase() async throws -> Bool {
        Self.log("purchase start: productID=\(Self.productID)")
        await syncPlanWithStore()
        if isPaid {
            Self.log("purchase skipped: already entitled")
            return true
        }
        Self.log("store environment: \(Self.storeEnvironmentSummary())")
        Self.log("bundle identifier: \(Bundle.main.bundleIdentifier ?? "unknown")")
        var products = try await Product.products(for: [Self.productID])
        Self.log("products fetched count=\(products.count), ids=\(products.map(\.id))")
        if products.isEmpty {
            Self.log("no products from first fetch -> trying AppStore.sync and retry fetch")
            do {
                try await AppStore.sync()
                Self.log("AppStore.sync succeeded before retry")
            } catch {
                Self.log("AppStore.sync failed before retry: \(error.localizedDescription)")
            }
            products = try await Product.products(for: [Self.productID])
            Self.log("retry fetched count=\(products.count), ids=\(products.map(\.id))")
        }
        guard let product = products.first else {
            Self.log("product not found for id=\(Self.productID)")
            throw PurchaseError.productNotFound
        }
        Self.log("purchase request: id=\(product.id), displayName=\(product.displayName), price=\(product.displayPrice)")
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                Self.log("purchase verified: transactionID=\(transaction.id), originalID=\(transaction.originalID), productID=\(transaction.productID)")
                await transactionFinishTracker.finishOnce(transaction)
                Self.log("transaction finished: id=\(transaction.id)")
                setPlan(.paid)
                return true
            case .unverified(_, let error):
                let details = error.localizedDescription
                Self.log("purchase unverified: \(details)")
                throw PurchaseError.verificationFailed(details)
            }
        case .userCancelled:
            Self.log("purchase cancelled by user")
            return false
        case .pending:
            Self.log("purchase pending approval")
            return false
        @unknown default:
            Self.log("purchase returned unknown result")
            return false
        }
    }

    @MainActor
    func restorePurchases() async {
        Self.log("restore start: productID=\(Self.productID)")
        Self.log("store environment: \(Self.storeEnvironmentSummary())")
        do {
            try await AppStore.sync()
            Self.log("AppStore.sync succeeded")
        } catch {
            Self.log("AppStore.sync failed: \(error.localizedDescription)")
        }
        let wasPaid = isPaid
        await syncPlanWithStore()
        Self.log("restore completed: wasPaid=\(wasPaid) -> currentPlan=\(currentPlan.rawValue)")
    }

    private func save() {
        UserDefaults.standard.set(currentPlan.rawValue, forKey: Self.storageKey)
    }
}
