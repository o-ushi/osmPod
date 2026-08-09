import SwiftUI
import SwiftData

struct CloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang

    @State private var syncManager = ICloudSyncManager.shared
    @State private var isSyncing = false

    var body: some View {
        let s = lang.strings
        Form {
            Section {
                Toggle(s.cloudSyncEnable, isOn: Binding(
                    get: { syncManager.isEnabled },
                    set: { syncManager.isEnabled = $0 }
                ))
            } footer: {
                Text(s.cloudSyncEnableFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            if syncManager.isEnabled {
                Section {
                    if !syncManager.isICloudAvailable {
                        // iCloud 未設定
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            Text(s.cloudSyncUnavailable)
                                .font(.footnote)
                        }
                        .padding(.vertical, 2)
                    } else {
                        // 最終同期日時
                        if let lastSync = syncManager.lastSyncDate {
                            HStack {
                                Label(s.cloudSyncLastSync, systemImage: "clock.arrow.circlepath")
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundStyle(AppPalette.textOnCardSecondary)
                                    .font(.footnote)
                            }
                        } else {
                            Label(s.cloudSyncNeverSynced, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(AppPalette.textOnCardSecondary)
                        }

                        // 今すぐ同期
                        Button {
                            Task { @MainActor in
                                isSyncing = true
                                syncManager.status = .idle
                                await syncManager.manualSync(context: modelContext)
                                isSyncing = false
                            }
                        } label: {
                            HStack {
                                Label(s.cloudSyncNow, systemImage: "arrow.triangle.2.circlepath")
                                if isSyncing || syncManager.status.isWorking {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSyncing || syncManager.status.isWorking)
                    }

                    if case .error(let msg) = syncManager.status {
                        Text(msg).foregroundStyle(.red).font(.footnote)
                    }
                } header: {
                    Text("iCloud")
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                } footer: {
                    Text(s.cloudSyncFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()
            }
        }
        .osmSubpageListChrome()
        .navigationTitle(s.cloudSync)
        .navigationBarTitleDisplayMode(.inline)
    }
}
