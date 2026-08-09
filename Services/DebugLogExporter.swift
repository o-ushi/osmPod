import Foundation
import OSLog
import UIKit

/// 開発者向けデバッグメニューから、直近の再生関連ログ（`bgLog` / `prepLog` など）を
/// 書き出すためのユーティリティ。
///
/// `OSLogStore(scope: .currentProcessIdentifier)` は特別な entitlement なしで
/// 自プロセスが出力した過去ログを遡って取得できるため、不具合の発生に後から気づいた
/// 場合でも（Console.app でリアルタイム監視していなくても）ログを回収できる。
/// 唯一の呼び出し元（`SettingsView` のログ共有ボタン）が Main Actor 上で同期的に呼ぶため、
/// `UIDevice.current` など Main Actor 隔離の API をそのまま使えるよう型ごと隔離する。
@MainActor
enum DebugLogExporter {
    private static let subsystem = "com.osamushikubo.osmPod"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 直近 `hoursBack` 時間分のログをテキストファイルへ書き出し、共有用の URL を返す。
    static func exportRecentLogs(hoursBack: Double = 6) throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: Date().addingTimeInterval(-hoursBack * 3600))
        let entries = try store.getEntries(at: position)

        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog,
                  logEntry.subsystem == subsystem
            else { continue }
            let time = dateFormatter.string(from: logEntry.date)
            lines.append("[\(time)] [\(logEntry.category)] \(logEntry.composedMessage)")
        }

        let body: String
        if lines.isEmpty {
            body = "直近\(Int(hoursBack))時間以内のログが見つかりませんでした。"
                + "（アプリが再起動されているとログストアが切り替わっている場合があります）"
        } else {
            body = lines.joined(separator: "\n")
        }

        let text = headerText(hoursBack: hoursBack) + "\n\n" + body

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osmPod-debug-log-\(Int(Date().timeIntervalSince1970)).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 共有テキスト先頭に付けるヘッダ（アプリバージョン・OS・開発者モード ON 時刻・収集範囲）。
    /// CS/LS ズレの再現ログを見返すとき、いつ・どのビルドの挙動かをすぐ確認できるようにする。
    private static func headerText(hoursBack: Double) -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = UIDevice.current.systemVersion
        let devModeOnAt = AppSettings.developerModeEnabledAt.map { dateFormatter.string(from: $0) } ?? "unknown"
        return [
            "osmPod debug log export",
            "appVersion=\(appVersion) (\(buildNumber))",
            "os=iOS \(osVersion)",
            "developerModeEnabledAt=\(devModeOnAt)",
            "rangeHoursBack=\(Int(hoursBack))",
            "exportedAt=\(dateFormatter.string(from: .now))",
        ].joined(separator: "\n")
    }
}
