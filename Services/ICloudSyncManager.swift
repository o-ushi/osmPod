import Foundation
import SwiftData

@MainActor
@Observable
final class ICloudSyncManager {
    static let shared = ICloudSyncManager()

    enum Status: Equatable {
        case idle
        case uploading
        case downloading
        case unavailable
        case error(String)

        var isWorking: Bool { self == .uploading || self == .downloading }
    }

    var status: Status = .idle

    var isEnabled: Bool {
        get { AppSettings.cloudSyncEnabled }
        set { AppSettings.cloudSyncEnabled = newValue }
    }

    var lastSyncDate: Date? {
        get { AppSettings.lastCloudSyncDate }
        set { AppSettings.lastCloudSyncDate = newValue }
    }

    /// iCloud にサインイン済みかどうか（entitlement があれば同期 OK）
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let dataKey = "osmPod-sync-v1"
    private let timestampKey = "osmPod-sync-v1-ts"
    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Observation

    /// アプリ起動時に一度だけ呼ぶ。他デバイスからの変更を自動受信する。
    func startObserving(context: ModelContext) {
        modelContext = context
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(self.dataKey) else { return }
            Task { @MainActor in
                guard self.isEnabled, let ctx = self.modelContext else { return }
                await self.download(context: ctx)
            }
        }
        kvStore.synchronize()
    }

    // MARK: - Sync API

    func syncOnForeground(context: ModelContext) async {
        guard isEnabled else { return }
        guard isICloudAvailable else { status = .unavailable; return }
        guard !status.isWorking else { return }
        kvStore.synchronize()
        let remoteTS = kvStore.double(forKey: timestampKey)
        let localTS = lastSyncDate?.timeIntervalSinceReferenceDate ?? 0
        if remoteTS > localTS {
            await download(context: context)
        }
    }

    func syncToCloud(context: ModelContext) async {
        guard isEnabled else { return }
        guard isICloudAvailable else { status = .unavailable; return }
        guard !status.isWorking else { return }
        await upload(context: context)
    }

    func manualSync(context: ModelContext) async {
        guard isEnabled else { return }
        guard isICloudAvailable else { status = .unavailable; return }
        guard !status.isWorking else { return }
        kvStore.synchronize()
        let remoteTS = kvStore.double(forKey: timestampKey)
        let localTS = lastSyncDate?.timeIntervalSinceReferenceDate ?? 0
        if remoteTS > localTS {
            await download(context: context)
        } else {
            await upload(context: context)
        }
    }

    /// Removes this app's complete KVS sync payload. Other devices with stale data must
    /// disable sync or reset as well to avoid uploading it again.
    func deleteCloudData() {
        kvStore.removeObject(forKey: dataKey)
        kvStore.removeObject(forKey: timestampKey)
        kvStore.synchronize()
        isEnabled = false
        lastSyncDate = nil
        status = .idle
    }

    // MARK: - Private

    private func upload(context: ModelContext) async {
        status = .uploading
        do {
            let payload = try LibraryImportExportService.buildFullExportPayload(context: context)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(payload)

            // KVS の上限は 1MB/値。超える場合はエラーで通知
            guard data.count < 1_000_000 else {
                throw SyncError.dataTooLarge(data.count)
            }

            kvStore.set(data, forKey: dataKey)
            kvStore.set(Date.now.timeIntervalSinceReferenceDate, forKey: timestampKey)
            kvStore.synchronize()

            lastSyncDate = .now
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func download(context: ModelContext) async {
        status = .downloading
        do {
            guard let data = kvStore.data(forKey: dataKey) else {
                status = .idle
                return
            }
            try await LibraryImportExportService.syncImport(data, context: context)
            lastSyncDate = .now
            status = .idle
        } catch {
            // 途中まで挿入した未保存の変更を破棄し、コンテキストを汚染しない。
            context.rollback()
            status = .error(error.localizedDescription)
        }
    }
}

private enum SyncError: LocalizedError {
    case dataTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .dataTooLarge(let bytes):
            let mb = String(format: "%.1f", Double(bytes) / 1_000_000)
            return "ライブラリデータ (\(mb) MB) が iCloud 同期の上限 (1 MB) を超えています。"
        }
    }
}
