import Foundation
import StoreKit
import SwiftUI
import UIKit

struct PlanManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var lang
    @State private var planStore = PlanStore.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alertMessage: String?

    var body: some View {
        let s = lang.strings
        NavigationStack {
            List {
                currentPlanSection(strings: s)
                limitsSection(strings: s)
                if planStore.isFree {
                    upgradeSection(strings: s)
                }
                #if DEBUG
                developerSection(strings: s)
                #endif
            }
            .osmSubpageListChrome()
            .navigationTitle(s.planManagementTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(s.close)
                }
            }
            .alert(s.planNoticeTitle, isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button(s.ok, role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    // MARK: - 現在のプラン

    private func currentPlanSection(strings s: LocalizedStrings) -> some View {
        Section {
            HStack(spacing: 16) {
                planIconView
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(s.planCurrentPlanLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(planStore.isFree ? s.planNameFree : s.planNamePremium)
                        .font(.title2.bold())
                        .foregroundStyle(planStore.isFree ? .primary : Color.orange)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 件数制限

    private func limitsSection(strings s: LocalizedStrings) -> some View {
        Section {
            HStack {
                Label(s.planShowLimitLabel, systemImage: "dot.radiowaves.left.and.right")
                Spacer()
                Text(planStore.isFree ? s.planLimitCountUnit(PlanStore.freeShowLimit) : s.planUnlimited)
                    .foregroundStyle(planStore.isFree ? .orange : .secondary)
                    .fontWeight(planStore.isFree ? .semibold : .regular)
            }
            HStack {
                Label(s.planFolderLimitLabel, systemImage: "folder")
                Spacer()
                Text(planStore.isFree ? s.planLimitCountUnit(PlanStore.freeFolderLimit) : s.planUnlimited)
                    .foregroundStyle(planStore.isFree ? .orange : .secondary)
                    .fontWeight(planStore.isFree ? .semibold : .regular)
            }
        } footer: {
            if planStore.isFree {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: s.planFreeShowLimitFooterFormat,
                            PlanStore.freeShowLimit
                        )
                    )
                    Text(
                        String(
                            format: s.planFreeFolderLimitFooterFormat,
                            PlanStore.freeFolderLimit
                        )
                    )
                }
            }
        }
    }

    // MARK: - アップグレード

    private func upgradeSection(strings s: LocalizedStrings) -> some View {
        Section {
            Button {
                Task { await performPurchase(strings: s) }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text(isPurchasing ? s.planProcessing : s.planUpgradeButton)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .disabled(isPurchasing || isRestoring)

            Button {
                Task { await performRestore(strings: s) }
            } label: {
                HStack {
                    if isRestoring { ProgressView().tint(.secondary) }
                    Text(isRestoring ? s.planRestoring : s.planRestorePurchases)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.secondary)
            .disabled(isPurchasing || isRestoring)
        }
    }

    // MARK: - 開発者
    //
    // 注意: これは Settings 画面下部を7回タップして開く `AppSettings.developerModeEnabled`
    // （ログ共有用のランタイム隠しメニュー）とは別物。こちらはコンパイル時の #if DEBUG のみで
    // 有効になるプラン切替シミュレータで、Release ビルドには含まれない。

    #if DEBUG
    private func developerSection(strings s: LocalizedStrings) -> some View {
        Section {
            Picker(s.planDeveloperTestPlan, selection: Binding(
                get: { planStore.currentPlan },
                set: { planStore.setPlan($0) }
            )) {
                Text(s.planNameFree).tag(AppPlan.free)
                Text(s.planNamePremium).tag(AppPlan.paid)
            }
            .pickerStyle(.segmented)

            Text(s.planDeveloperFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(s.planDeveloperSectionTitle)
        }
    }
    #endif

    private var planIconView: some View {
        Group {
            let imageName = planStore.isFree ? "AppImageFree" : "AppImage"
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(
                            LinearGradient(
                                colors: planStore.isFree
                                    ? [.gray, .gray.opacity(0.7)]
                                    : [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: planStore.isFree ? "dot.radiowaves.left.and.right" : "crown.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @MainActor
    private func performPurchase(strings s: LocalizedStrings) async {
        print("[IAP] upgrade button tapped, productID=\(PlanStore.productID)")
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let purchased = try await planStore.purchase()
            if purchased {
                alertMessage = s.planPurchaseSuccess
            }
        } catch {
            print("[IAP] purchase error: \(error.localizedDescription)")
            print("[IAP] purchase error detail: \(String(reflecting: error))")
            alertMessage = purchaseErrorMessage(error, strings: s)
        }
    }

    private func purchaseErrorMessage(_ error: Error, strings: LocalizedStrings) -> String {
        if let purchaseError = error as? PurchaseError {
            return purchaseError.localizedDescription
        }
        if let sk = error as? StoreKitError {
            switch sk {
            case .networkError:
                return strings.planPurchaseErrorNetwork
            case .notAvailableInStorefront:
                return strings.planPurchaseErrorUnavailable
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return strings.planPurchaseErrorNetwork
        }
        return strings.planPurchaseErrorGeneric
    }

    @MainActor
    private func performRestore(strings s: LocalizedStrings) async {
        print("[IAP] restore button tapped, productID=\(PlanStore.productID)")
        isRestoring = true
        defer { isRestoring = false }
        await planStore.restorePurchases()
        if planStore.isPaid {
            alertMessage = s.planRestoreSuccess
        } else {
            alertMessage = s.planRestoreNothingFound
        }
    }
}

#Preview("FREE") {
    PlanManagementView()
        .environment(LanguageSettings())
}
