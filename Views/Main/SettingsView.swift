import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageSettings.self) private var lang

    @State private var enableHaptic = AppSettings.enableHapticFeedback
    @State private var hapticIntensity = AppSettings.hapticIntensity
    @State private var enableSound = AppSettings.enableSoundFeedback
    @State private var soundVolume = AppSettings.soundVolume
    @State private var dateFormat = AppSettings.dateFormat
    @State private var soundVolumePreviewTask: Task<Void, Never>?

    // 開発者向け隠しメニュー: 設定画面最下部を7回タップすると表示が切り替わる（ログ共有用、Release でも有効）。
    // `PlanManagementView` の #if DEBUG プラン切替シミュレータとは別物。
    @State private var developerModeEnabled = AppSettings.developerModeEnabled
    @State private var devTapCount = 0
    @State private var devModeToastMessage: String?
    @State private var devModeToastTask: Task<Void, Never>?
    @State private var debugLogShareItem: DebugLogShareItem?
    @State private var debugLogExportFailed = false
    @State private var showDebugLogDisclosure = false

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        @Bindable var bindableLang = lang
        let s = lang.strings

        NavigationStack {
            Form {
                // 🌐 言語
                Section {
                    Picker(s.languageSection, selection: $bindableLang.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text("\(language.flag) \(language.displayName)")
                                .tag(language)
                        }
                    }
                } header: {
                    Text(s.languageSection)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                } footer: {
                    Text(s.languageFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // 📅 日付表示
                Section {
                    Picker(s.dateFormatSection, selection: $dateFormat) {
                        ForEach(DateFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dateFormat) { _, v in
                        AppSettings.dateFormat = v
                    }
                } header: {
                    Text(s.dateFormatSection)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                } footer: {
                    Text(s.dateFormatFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // 📳 フィードバック
                Section {
                    if !isIPad {
                        Toggle(s.hapticFeedback, isOn: $enableHaptic)
                            .onChange(of: enableHaptic) { _, v in
                                AppSettings.enableHapticFeedback = v
                                if v { HapticManager.shared.provideFeedback() }
                            }

                        if enableHaptic {
                            Picker(s.hapticIntensityLabel, selection: $hapticIntensity) {
                                ForEach(HapticIntensity.allCases) { intensity in
                                    Text(intensity.displayName(language: lang.language)).tag(intensity)
                                }
                            }
                            .onChange(of: hapticIntensity) { _, _ in
                                AppSettings.hapticIntensity = hapticIntensity
                                HapticManager.shared.provideFeedback()
                            }
                        }
                    }

                    Toggle(s.soundFeedback, isOn: $enableSound)
                        .onChange(of: enableSound) { _, v in
                            AppSettings.enableSoundFeedback = v
                            if v { HapticManager.shared.provideFeedback() }
                        }

                    if enableSound {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(s.soundVolume)
                                Spacer()
                                Text("\(Int(soundVolume * 100))%")
                                    .foregroundStyle(AppPalette.textOnCardSecondary)
                            }
                            Slider(value: $soundVolume, in: 0...1, step: 0.1)
                                .onChange(of: soundVolume) { _, v in
                                    scheduleSoundVolumePersistAndPreview(v)
                                }
                        }
                    }
                } header: {
                    Text(s.feedback)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                } footer: {
                    Text(s.feedbackFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // 🎚 再生オプション（シェイク巻き戻し・再生済み・自動再生をまとめたグループ）
                Section {
                    NavigationLink {
                        PlaybackOptionsView()
                    } label: {
                        Label(s.playbackOptions, systemImage: "play.circle")
                    }
                } footer: {
                    Text(s.playbackOptionsFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // 💾 データ管理（iCloud同期・バックアップ管理をまとめたグループ）
                Section {
                    NavigationLink {
                        DataManagementGroupView()
                    } label: {
                        Label(s.dataManagementGroup, systemImage: "externaldrive")
                    }
                } footer: {
                    Text(s.dataManagementGroupFooter)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // プライバシー（一番下に配置）
                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label(PrivacyText.title(lang.language), systemImage: "hand.raised")
                    }
                } footer: {
                    Text(PrivacyText.linkFooter(lang.language))
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()

                // 🛠 開発者向け（設定画面最下部を7回タップすると表示/非表示が切り替わる隠しメニュー）
                if developerModeEnabled {
                    Section {
                        Button {
                            showDebugLogDisclosure = true
                        } label: {
                            Label(s.shareDebugLogButton, systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text(s.developerModeSection)
                            .foregroundStyle(AppPalette.textOnSubpageSecondary)
                    } footer: {
                        Text(s.shareDebugLogFooter)
                            .foregroundStyle(AppPalette.textOnSubpageSecondary)
                    }
                    .osmSettingsCardRow()
                }

                Section {
                    Color.clear
                        .frame(height: 40)
                        .contentShape(Rectangle())
                        .onTapGesture { registerDevAreaTap(strings: s) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .osmSubpageListChrome()
            .navigationTitle(s.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                enableHaptic = AppSettings.enableHapticFeedback
                hapticIntensity = AppSettings.hapticIntensity
                enableSound = AppSettings.enableSoundFeedback
                soundVolume = AppSettings.soundVolume
                dateFormat = AppSettings.dateFormat
                developerModeEnabled = AppSettings.developerModeEnabled
            }
            .onDisappear {
                soundVolumePreviewTask?.cancel()
                soundVolumePreviewTask = nil
                devModeToastTask?.cancel()
                devModeToastTask = nil
            }
            .overlay(alignment: .bottom) {
                if let devModeToastMessage {
                    Text(devModeToastMessage)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppPalette.cardFill, in: Capsule())
                        .foregroundStyle(AppPalette.textOnCardPrimary)
                        .overlay {
                            Capsule().strokeBorder(AppPalette.cardBorder, lineWidth: 1)
                        }
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $debugLogShareItem) { item in
                ActivityShareSheet(items: [item.url])
                    .onDisappear {
                        try? FileManager.default.removeItem(at: item.url)
                        debugLogShareItem = nil
                    }
            }
            .alert(s.shareDebugLogFailedMessage, isPresented: $debugLogExportFailed) {
                Button(s.ok) {}
            }
            .alert(PrivacyText.logConfirmTitle(lang.language), isPresented: $showDebugLogDisclosure) {
                Button(s.cancel, role: .cancel) {}
                Button(PrivacyText.shareLog(lang.language)) {
                    exportAndShareDebugLog()
                }
            } message: {
                Text(PrivacyText.logContents(lang.language))
            }
        }
    }

    private func registerDevAreaTap(strings s: LocalizedStrings) {
        devTapCount += 1
        guard devTapCount >= 7 else { return }
        devTapCount = 0
        developerModeEnabled.toggle()
        AppSettings.developerModeEnabled = developerModeEnabled
        if developerModeEnabled {
            AppSettings.developerModeEnabledAt = .now
        }
        HapticManager.shared.provideFeedback()
        showDevModeToast(developerModeEnabled ? s.developerModeEnabledMessage : s.developerModeDisabledMessage)
    }

    private func showDevModeToast(_ message: String) {
        devModeToastTask?.cancel()
        withAnimation { devModeToastMessage = message }
        devModeToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { devModeToastMessage = nil }
        }
    }

    private func exportAndShareDebugLog() {
        do {
            let url = try DebugLogExporter.exportRecentLogs()
            debugLogShareItem = DebugLogShareItem(url: url)
        } catch {
            debugLogExportFailed = true
        }
    }

    /// スライダー操作中の連続プレビュー・UserDefaults 書き込みで UI が固まるのを防ぐ。
    private func scheduleSoundVolumePersistAndPreview(_ volume: Double) {
        soundVolumePreviewTask?.cancel()
        soundVolumePreviewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            AppSettings.soundVolume = volume
            HapticManager.shared.previewSound(volume: volume)
        }
    }

}

enum PrivacyPolicyLinks {
    // 閲覧専用リンク（/preview）。編集用の /edit リンクだとリンク共有権限次第で
    // 第三者が編集できてしまうため使わない。あわせて Google ドキュメント側の
    // 「リンクを知っている全員」共有権限が「閲覧者」になっていることも確認すること。
    static let externalPolicy = URL(string: "https://docs.google.com/document/d/1pIMDhVRfQz6ae310EAIypjeiLDToNREpHiWSwPKPIno/preview")!
    static let applePrivacy = URL(string: "https://www.apple.com/legal/privacy/")!
    static let appleMediaServicesTerms = URL(string: "https://www.apple.com/legal/internet-services/itunes/")!
    static let googlePrivacy = URL(string: "https://policies.google.com/privacy")!
}

enum PrivacyText {
    static func text(_ language: AppLanguage, _ ja: String, _ en: String, _ vi: String) -> String {
        switch language {
        case .japanese: ja
        case .english: en
        case .vietnamese: vi
        }
    }

    static func title(_ l: AppLanguage) -> String {
        text(l, "プライバシー", "Privacy", "Quyền riêng tư")
    }
    static func linkFooter(_ l: AppLanguage) -> String {
        text(l, "データの取得・共有・保存・削除について確認できます。", "Review how data is fetched, shared, stored, and deleted.", "Xem cách dữ liệu được tải, chia sẻ, lưu và xóa.")
    }
    static func logConfirmTitle(_ l: AppLanguage) -> String {
        text(l, "共有するログの内容", "Log contents to be shared", "Nội dung nhật ký sẽ chia sẻ")
    }
    static func shareLog(_ l: AppLanguage) -> String {
        text(l, "確認して共有", "Review and Share", "Xem và chia sẻ")
    }
    static func consentFirstLaunchIntro(_ l: AppLanguage) -> String {
        text(
            l,
            "はじめに、外部サービスへの送信について確認してください。内容を確認のうえ、同意するかどうかを選んでください。",
            "Before you start, please review how data is sent to external services below, then choose whether to agree.",
            "Trước khi bắt đầu, vui lòng xem cách dữ liệu được gửi đến dịch vụ bên ngoài ở dưới, rồi chọn đồng ý hay không."
        )
    }
    static func consentSectionHeader(_ l: AppLanguage) -> String {
        text(l, "番組検索（iTunes Search API）への送信", "Podcast Search (iTunes Search API)", "Tìm podcast (iTunes Search API)")
    }
    static func consentFooter(_ l: AppLanguage) -> String {
        text(
            l,
            "番組を検索するには、検索語と国コードをAppleのiTunes Search APIへ送信することへの同意が必要です。同意しない場合、番組検索とおすすめ表示は利用できませんが、登録済み番組の更新・再生には影響しません。この設定はいつでも変更できます。",
            "Searching for podcasts requires agreeing to send your search term and country code to Apple's iTunes Search API. If you decline, podcast search and recommendations are unavailable, but updating or playing already-registered shows is unaffected. You can change this anytime.",
            "Để tìm podcast, bạn cần đồng ý gửi từ khóa tìm kiếm và mã quốc gia đến iTunes Search API của Apple. Nếu từ chối, tính năng tìm kiếm và gợi ý podcast sẽ không khả dụng, nhưng việc cập nhật/phát các chương trình đã đăng ký không bị ảnh hưởng. Bạn có thể thay đổi cài đặt này bất cứ lúc nào."
        )
    }
    static func consentStatusGranted(_ l: AppLanguage) -> String {
        text(l, "同意済み — 番組検索を利用できます。", "Agreed — podcast search is available.", "Đã đồng ý — có thể tìm podcast.")
    }
    static func consentStatusDeclined(_ l: AppLanguage) -> String {
        text(l, "未同意 — 番組検索は利用できません。", "Not agreed — podcast search is unavailable.", "Chưa đồng ý — không thể tìm podcast.")
    }
    static func consentAgreeButton(_ l: AppLanguage) -> String {
        text(l, "同意する", "Agree", "Đồng ý")
    }
    static func consentDeclineButton(_ l: AppLanguage) -> String {
        text(l, "同意しない", "Decline", "Không đồng ý")
    }
    static func consentWithdrawButton(_ l: AppLanguage) -> String {
        text(l, "同意を取り消す", "Withdraw consent", "Rút lại đồng ý")
    }
    static func consentRequiredMessage(_ l: AppLanguage) -> String {
        text(
            l,
            "番組検索を利用するには、iTunes Search APIへの送信に同意してください。設定 > プライバシー、またはヘルプ > プライバシーから変更できます。",
            "To search for podcasts, please agree to sending data to the iTunes Search API. You can change this from Settings > Privacy or Help > Privacy.",
            "Để tìm podcast, vui lòng đồng ý gửi dữ liệu đến iTunes Search API. Bạn có thể thay đổi ở Cài đặt > Quyền riêng tư hoặc Trợ giúp > Quyền riêng tư."
        )
    }
    static func logContents(_ l: AppLanguage) -> String {
        text(
            l,
            "直近6時間のosmPodプロセス内ログをテキスト化します。日時、ログ分類、再生・通信・File Provider準備の状態やエラー、番組・エピソードのURLまたは名称がログ文に含まれる場合があります。共有先は次の画面で選びます。",
            "A text file is created from osmPod process logs for the last 6 hours. It includes timestamps, log categories, playback/network/File Provider preparation status and errors, and may include show or episode URLs or names in log messages. You choose the recipient on the next screen.",
            "Tệp văn bản được tạo từ nhật ký tiến trình osmPod trong 6 giờ gần nhất. Tệp gồm thời gian, loại nhật ký, trạng thái/lỗi phát, mạng, chuẩn bị File Provider và có thể có URL hoặc tên chương trình/tập. Bạn chọn nơi nhận ở màn hình tiếp theo."
        )
    }
}

struct PrivacyView: View {
    @Environment(LanguageSettings.self) private var lang
    var requiresDecision: Bool = false

    @State private var isGranted: Bool = ThirdPartyDataConsent.isGranted

    var body: some View {
        let l = lang.language
        List {
            if requiresDecision {
                Section {
                    Text(PrivacyText.consentFirstLaunchIntro(l))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .osmSettingsCardRow()
            }

            Section {
                if requiresDecision {
                    Text(isGranted ? PrivacyText.consentStatusGranted(l) : PrivacyText.consentStatusDeclined(l))
                        .foregroundStyle(AppPalette.textOnCardSecondary)
                } else {
                    HStack {
                        Text(isGranted ? PrivacyText.consentStatusGranted(l) : PrivacyText.consentStatusDeclined(l))
                        Spacer()
                    }
                    Button {
                        if isGranted {
                            ThirdPartyDataConsent.decline()
                        } else {
                            ThirdPartyDataConsent.grant()
                        }
                        isGranted = ThirdPartyDataConsent.isGranted
                    } label: {
                        Text(isGranted ? PrivacyText.consentWithdrawButton(l) : PrivacyText.consentAgreeButton(l))
                    }
                }
            } header: {
                Text(PrivacyText.consentSectionHeader(l))
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            } footer: {
                Text(PrivacyText.consentFooter(l))
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            privacySection(
                title: PrivacyText.text(l, "検索・RSS・メディア通信", "Search, RSS, and media connections", "Tìm kiếm, RSS và kết nối media"),
                body: PrivacyText.text(
                    l,
                    "番組検索では検索語と国コードをAppleのiTunes Search APIへ送信します。登録時とアプリ起動・復帰後および利用中の自動更新では、登録済みRSS URLへ接続して番組・エピソード情報を取得します。再生音声と番組画像は配信者またはそのCDNから取得され、接続先にはIPアドレス等が伝わります。Google AIは毎回の確認後にSafariで開き、osmPodのサーバーを経由しません。",
                    "Podcast search sends the search term and country code to Apple’s iTunes Search API. On registration and automatic refresh after launch/foreground and while in use, the app connects to saved RSS URLs for show and episode data. Audio and artwork are fetched from publishers or their CDNs, which receive connection data such as your IP address. Google AI opens in Safari only after per-use confirmation and does not pass through an osmPod server.",
                    "Tìm podcast gửi từ khóa và mã quốc gia đến iTunes Search API của Apple. Khi đăng ký và tự động cập nhật lúc mở/đưa app lên trước và trong khi dùng, app kết nối URL RSS đã lưu. Âm thanh và ảnh được tải từ nhà phát hành hoặc CDN, nơi có thể nhận dữ liệu kết nối như địa chỉ IP. Google AI chỉ mở trong Safari sau xác nhận mỗi lần và không qua máy chủ osmPod."
                )
            )
            privacySection(
                title: PrivacyText.text(l, "iCloud KVS同期", "iCloud KVS sync", "Đồng bộ iCloud KVS"),
                body: PrivacyText.text(
                    l,
                    "同期を有効にすると、データ形式version/書出日時、RSS URL、フォルダ名・アイコン・順序・階層と番組/エピソード割当、状態を持つエピソードの番組RSS URL・音声URL・再生済み・再生位置・取得済み時間・新着・お気に入りをAppleのiCloud Key-Value Storeへ保存し、同じApple IDの端末間で同期します。アプリ設定、ダウンロード音声、画像は含めません。",
                    "When enabled, Apple iCloud Key-Value Store receives the data-format version/export date, RSS URLs, folder names/icons/order/hierarchy and show/episode assignments, plus each state-bearing episode’s show RSS URL, audio URL, played status, playback position/known duration, new status, and favorite status. It syncs across devices using the same Apple ID. App preferences, downloaded audio, and images are excluded.",
                    "Khi bật, Apple iCloud Key-Value Store nhận phiên bản định dạng/ngày xuất, URL RSS, tên/biểu tượng/thứ tự/cấu trúc thư mục và liên kết chương trình/tập; cùng URL RSS chương trình, URL âm thanh, trạng thái đã phát, vị trí/thời lượng đã biết, trạng thái mới và yêu thích của các tập có trạng thái. Dữ liệu đồng bộ giữa thiết bị cùng Apple ID. Không gồm cài đặt app, âm thanh tải xuống hay ảnh."
                )
            )
            privacySection(
                title: PrivacyText.text(l, "ファイルと共有", "Files and sharing", "Tệp và chia sẻ"),
                body: PrivacyText.text(
                    l,
                    "ユーザーが選んだローカル/クラウドファイルには、セキュリティスコープ付きブックマークを保存して再アクセスします。File Provider（iCloud Drive、Dropbox等）がファイルを準備する際は各事業者の処理が発生します。共有Extensionが受け取ったURLは端末内の名前付きペーストボードへ一時保存し、取込後に消去します。ライブラリJSONと診断ログはユーザーが共有先を選んだ場合だけ外部へ渡ります。",
                    "For user-selected local/cloud files, security-scoped bookmarks are stored for later access. File Provider services such as iCloud Drive or Dropbox process files when preparing them. The Share Extension temporarily stores received URLs on a device-only named pasteboard and clears them after import. Library JSON and diagnostic logs leave the app only when you choose a share destination.",
                    "Với tệp cục bộ/đám mây do bạn chọn, app lưu bookmark phạm vi bảo mật để truy cập lại. Dịch vụ File Provider như iCloud Drive hoặc Dropbox xử lý tệp khi chuẩn bị. Share Extension tạm lưu URL nhận được trên pasteboard đặt tên trong thiết bị và xóa sau khi nhập. JSON thư viện và nhật ký chẩn đoán chỉ ra ngoài khi bạn chọn nơi chia sẻ."
                )
            )
            privacySection(
                title: PrivacyText.text(l, "保存期間と削除", "Retention and deletion", "Lưu giữ và xóa"),
                body: PrivacyText.text(
                    l,
                    "ライブラリ、設定、ダウンロード、取込ファイル、ブックマークは削除またはFactory Resetまで端末に保持されます。画像キャッシュと共有一時データは必要に応じて消去されます。Factory Resetは端末データを削除し、選択した場合はiCloud KVS上の同期データも削除します。iCloud削除後、古いデータを持つ別端末が再アップロードする可能性があるため、全端末で同期を停止またはリセットしてください。",
                    "Library data, preferences, downloads, imported files, and bookmarks remain on device until deleted or Factory Reset. Image cache and share temporary data may be cleared as needed. Factory Reset deletes device data and, if selected, iCloud KVS sync data. A device holding an older copy may upload it again, so disable sync or reset all devices.",
                    "Dữ liệu thư viện, cài đặt, tệp tải/nhập và bookmark được giữ trên thiết bị đến khi xóa hoặc Factory Reset. Bộ nhớ đệm ảnh và dữ liệu chia sẻ tạm có thể được dọn. Factory Reset xóa dữ liệu thiết bị và, nếu chọn, dữ liệu đồng bộ iCloud KVS. Thiết bị khác có bản cũ có thể tải lại lên; hãy tắt đồng bộ hoặc đặt lại mọi thiết bị."
                )
            )
            Section {
                Link(destination: PrivacyPolicyLinks.externalPolicy) {
                    Label(
                        PrivacyText.text(l, "osmPod プライバシーポリシー", "osmPod Privacy Policy", "Chính sách quyền riêng tư osmPod"),
                        systemImage: "doc.text"
                    )
                }
            } footer: {
                Text(PrivacyText.text(l, "外部サービスへの送信、iCloud同期、保存期間などの詳細を記載しています。", "Details on external service transmissions, iCloud sync, and data retention.", "Chi tiết về gửi dữ liệu đến dịch vụ bên ngoài, đồng bộ iCloud và thời gian lưu giữ."))
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()
            Section {
                Link(destination: PrivacyPolicyLinks.applePrivacy) {
                    Label(
                        PrivacyText.text(l, "Apple プライバシーポリシー", "Apple Privacy Policy", "Chính sách quyền riêng tư Apple"),
                        systemImage: "applelogo"
                    )
                }
                Link(destination: PrivacyPolicyLinks.appleMediaServicesTerms) {
                    Label(
                        PrivacyText.text(l, "Apple メディアサービス利用規約", "Apple Media Services Terms", "Điều khoản Dịch vụ Media của Apple"),
                        systemImage: "applelogo"
                    )
                }
                Link(destination: PrivacyPolicyLinks.googlePrivacy) {
                    Label(
                        PrivacyText.text(l, "Google プライバシーポリシー", "Google Privacy Policy", "Chính sách quyền riêng tư Google"),
                        systemImage: "safari"
                    )
                }
            } header: {
                Text(PrivacyText.text(l, "関連ポリシー", "Related Policies", "Chính sách liên quan"))
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            } footer: {
                Text(PrivacyText.text(l, "iTunes Search APIおよびApple配信メディアにはAppleの規約が、Google AI検索機能にはGoogleのポリシーが適用されます。", "Apple's terms apply to the iTunes Search API and Apple-hosted media; Google's policy applies to the Google AI search feature.", "Điều khoản của Apple áp dụng cho iTunes Search API và media qua Apple; chính sách của Google áp dụng cho tính năng tìm kiếm AI của Google."))
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            if requiresDecision {
                Section {
                    Button {
                        ThirdPartyDataConsent.grant()
                        isGranted = true
                    } label: {
                        Text(PrivacyText.consentAgreeButton(l))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .padding(12)

                    Button {
                        ThirdPartyDataConsent.decline()
                        isGranted = false
                    } label: {
                        Text(PrivacyText.consentDeclineButton(l))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .listRowBackground(Color.clear)
            }
        }
        .osmSubpageListChrome()
        .navigationTitle(PrivacyText.title(l))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(requiresDecision)
        .onAppear {
            isGranted = ThirdPartyDataConsent.isGranted
        }
    }

    private func privacySection(title: String, body: String) -> some View {
        Section {
            Text(body)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(title)
                .foregroundStyle(AppPalette.textOnSubpageSecondary)
        }
        .osmSettingsCardRow()
    }
}

struct AutoPlayExcludedShowsView: View {
    @Environment(LanguageSettings.self) private var lang
    @Query(sort: [SortDescriptor(\Show.title)]) private var shows: [Show]
    @State private var excludedFeedURLs: Set<String> = []

    private var hasDuplicateTitles: Bool {
        !ShowDuplicateMergeService.duplicateGroups(from: shows).isEmpty
    }

    var body: some View {
        let s = lang.strings
        List {
            if hasDuplicateTitles {
                Section {
                    NavigationLink {
                        ShowManagementView()
                    } label: {
                        Label(s.showManagementMergeButton, systemImage: "arrow.triangle.merge")
                    }
                } footer: {
                    Text(s.autoPlayExcludedShowsDuplicateHint)
                        .foregroundStyle(AppPalette.textOnSubpageSecondary)
                }
                .osmSettingsCardRow()
            }

            Section {
                ForEach(shows) { show in
                    Button {
                        if excludedFeedURLs.contains(show.feedURL) {
                            excludedFeedURLs.remove(show.feedURL)
                        } else {
                            excludedFeedURLs.insert(show.feedURL)
                        }
                    } label: {
                        HStack {
                            Text(show.title)
                                .foregroundStyle(AppPalette.textOnCardPrimary)
                            Spacer()
                            if excludedFeedURLs.contains(show.feedURL) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppPalette.accentColor)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(AppPalette.textOnCardSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(s.autoPlayExcludedShowsFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()
        }
        .osmSubpageListChrome()
        .navigationTitle(s.autoPlayExcludedShowsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            excludedFeedURLs = AppSettings.autoPlayExcludedShowFeedURLs
        }
        .onDisappear {
            AppSettings.autoPlayExcludedShowFeedURLs = excludedFeedURLs
        }
    }
}

struct PlaybackOptionsView: View {
    @Environment(LanguageSettings.self) private var lang
    @State private var skipPlayedEpisodes = AppSettings.skipPlayedEpisodes
    @State private var hidePlayedEpisodes = AppSettings.hidePlayedEpisodes
    @State private var autoPlayEnabled = AppSettings.autoPlayEnabled
    @State private var autoPlayOrder = AppSettings.autoPlayOrder

    var body: some View {
        let s = lang.strings
        Form {
            // 🔀 シェイクで巻き戻す時間
            Section {
                NavigationLink {
                    ShakeRewindSettingsDetailView()
                } label: {
                    HStack {
                        Text(s.shakeRewindDuration)
                        Spacer()
                        Text(s.secondsLabel(Int(AppSettings.shakeRewindSeconds)))
                            .foregroundStyle(AppPalette.textOnCardSecondary)
                    }
                }
            } footer: {
                Text(s.shakeRewindFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            // ✅ 再生済みエピソード
            Section {
                Toggle(s.skipPlayedLabel, isOn: $skipPlayedEpisodes)
                    .onChange(of: skipPlayedEpisodes) { _, v in
                        AppSettings.skipPlayedEpisodes = v
                    }
                Toggle(s.hidePlayedLabel, isOn: $hidePlayedEpisodes)
                    .onChange(of: hidePlayedEpisodes) { _, v in
                        AppSettings.hidePlayedEpisodes = v
                    }
            } header: {
                Text(s.playedEpisodesSection)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.skipPlayedEpisodesFooter)
                    Text(s.hidePlayedEpisodesFooter)
                }
                .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            // 🔄 再生終了後
            Section {
                Toggle(s.autoPlayNextEpisodeLabel, isOn: $autoPlayEnabled)
                    .onChange(of: autoPlayEnabled) { _, v in
                        AppSettings.autoPlayEnabled = v
                    }
                if autoPlayEnabled {
                    Picker(s.autoPlayOrderLabel, selection: $autoPlayOrder) {
                        ForEach(AutoPlayOrder.allCases) { order in
                            Text(order.displayName(language: lang.language)).tag(order)
                        }
                    }
                    .onChange(of: autoPlayOrder) { _, v in
                        AppSettings.autoPlayOrder = v
                    }
                    NavigationLink {
                        AutoPlayExcludedShowsView()
                    } label: {
                        Text(s.autoPlayExcludedShowsButton)
                    }
                }
            } header: {
                Text(s.autoPlaySection)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            } footer: {
                Text(s.autoPlaySectionFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()
        }
        .osmSubpageListChrome()
        .navigationTitle(s.playbackOptions)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            skipPlayedEpisodes = AppSettings.skipPlayedEpisodes
            hidePlayedEpisodes = AppSettings.hidePlayedEpisodes
            autoPlayEnabled = AppSettings.autoPlayEnabled
            autoPlayOrder = AppSettings.autoPlayOrder
        }
    }
}

struct DataManagementGroupView: View {
    @Environment(LanguageSettings.self) private var lang

    var body: some View {
        let s = lang.strings
        Form {
            // ☁️ iCloud 同期
            Section {
                NavigationLink {
                    CloudSyncSettingsView()
                } label: {
                    Label(s.cloudSync, systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            } footer: {
                Text(s.cloudSyncSectionFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()

            // 💾 データ管理
            Section {
                NavigationLink {
                    DataManagementView()
                } label: {
                    Label(s.dataManagement, systemImage: "externaldrive")
                }
            } footer: {
                Text(s.dataManagementFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()
        }
        .osmSubpageListChrome()
        .navigationTitle(s.dataManagementGroup)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShakeRewindSettingsDetailView: View {
    @Environment(LanguageSettings.self) private var lang
    @State private var rewindSeconds: Double = AppSettings.shakeRewindSeconds

    var body: some View {
        let s = lang.strings
        Form {
            Section {
                Stepper(
                    value: $rewindSeconds,
                    in: 5...180,
                    step: 5
                ) {
                    HStack {
                        Text(s.rewindSeconds)
                        Spacer()
                        Text(s.secondsLabel(Int(rewindSeconds)))
                            .foregroundStyle(AppPalette.textOnCardSecondary)
                    }
                }
                .onChange(of: rewindSeconds) { _, v in
                    AppSettings.shakeRewindSeconds = v
                }
            } footer: {
                Text(s.shakeRewindFooter)
                    .foregroundStyle(AppPalette.textOnSubpageSecondary)
            }
            .osmSettingsCardRow()
        }
        .osmSubpageListChrome()
        .navigationTitle(s.shakeRewindDuration)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            rewindSeconds = AppSettings.shakeRewindSeconds
        }
    }
}

/// 開発者向け「再生ログを共有」で書き出したファイルを `.sheet(item:)` に渡すためのラッパー。
private struct DebugLogShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// `UIActivityViewController` の SwiftUI ラッパー。ファイル URL の共有には
/// `ShareLink` よりもこちらの方が Mail 添付などで確実に動作する。
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
