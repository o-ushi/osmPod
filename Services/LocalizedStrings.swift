import Foundation

struct LocalizedStrings {
    let language: AppLanguage

    /// `LanguageSettings` や SwiftUI 環境の外（エラー型・パーサーなど）から参照するとき用。
    static var current: LocalizedStrings {
        let lang: AppLanguage = {
            if let raw = UserDefaults.standard.string(forKey: "appLanguage"),
               let saved = AppLanguage(rawValue: raw) {
                return saved
            }
            return AppLanguage.defaultInstallLanguage
        }()
        return LocalizedStrings(language: lang)
    }

    private func t(_ ja: String, _ en: String, _ vi: String) -> String {
        switch language {
        case .japanese: return ja
        case .english: return en
        case .vietnamese: return vi
        }
    }

    // MARK: - General

    var done: String { t("完了", "Done", "Xong") }
    var cancel: String { t("キャンセル", "Cancel", "Hủy") }
    var ok: String { "OK" }
    var retry: String { t("再試行", "Retry", "Thử lại") }
    var delete: String { t("削除", "Delete", "Xóa") }
    var save: String { t("保存", "Save", "Lưu") }
    var close: String { t("閉じる", "Close", "Đóng") }
    var search: String { t("検索", "Search", "Tìm kiếm") }
    var ascending: String { t("昇順", "Ascending", "Tăng dần") }
    var selectAll: String { t("すべて選択", "Select All", "Chọn tất cả") }
    var deselectAll: String { t("選択を解除", "Deselect All", "Bỏ chọn tất cả") }
    var error: String { t("エラー", "Error", "Lỗi") }
    var register: String { t("登録", "Register", "Đăng ký") }
    var create: String { t("作成", "Create", "Tạo") }
    var ascending_on: String { t("オン（昇順）", "On (Ascending)", "Bật (Tăng dần)") }
    var ascending_off: String { t("オフ（降順）", "Off (Descending)", "Tắt (Giảm dần)") }

    // MARK: - Main

    var appTitle: String { "osmPod" }
    var addShow: String { t("番組を追加", "Add Show", "Thêm chương trình") }
    var createFolder: String { t("フォルダを作成", "Create Folder", "Tạo thư mục") }
    var addEpisodeToFolder: String { t("エピソードをフォルダに追加", "Add Episodes to Folder", "Thêm tập vào thư mục") }
    var settings: String { t("設定", "Settings", "Cài đặt") }
    var planManagementMenu: String { t("プラン管理", "Plan Management", "Quản lý gói") }
    var help: String { t("ヘルプ", "Help", "Trợ giúp") }
    var menuLabel: String { t("メニュー", "Menu", "Menu") }
    var randomModeLabel: String { t("ランダム再生", "Random Play", "Phát ngẫu nhiên") }
    var randomModeOn: String { t("ランダム再生オン", "Random Play On", "Phát ngẫu nhiên: Bật") }
    var randomModeOff: String { t("ランダム再生オフ", "Random Play Off", "Phát ngẫu nhiên: Tắt") }
    var skipToNextEpisode: String { t("次のエピソードへスキップ", "Skip to Next Episode", "Chuyển sang tập tiếp theo") }
    var noFoldersYet: String { t("フォルダがまだありません", "No Folders Yet", "Chưa có thư mục") }
    var noFoldersDescription: String {
        t(
            "まずは右上のメニュー（⋯）から「番組を追加」を選んでください。",
            "Please select \"Add Show\" from the menu (⋯) in the upper right.",
            "Vui lòng chọn \"Thêm chương trình\" từ menu (⋯) ở góc trên bên phải."
        )
    }
    var searchPrompt: String { t("タイトル・番組名・概要で検索", "Search by title, show, or description", "Tìm theo tiêu đề, chương trình hoặc mô tả") }

    func episodeCountLabel(_ n: Int) -> String {
        t("\(n)件のエピソード", "\(n) episodes", "\(n) tập")
    }

    // MARK: - Default folder names (seeded on first launch)

    var defaultFolderFavorites: String { t("お気に入り", "Favorites", "Yêu thích") }
    var defaultFolderListenLater: String { t("あとで聴く", "Listen Later", "Nghe sau") }
    var defaultFolderStudy: String { t("学習用", "For Study", "Học tập") }
    var defaultFolderImport: String { t("インポート", "Import", "Nhập") }

    var untitledShow: String { t("無題の番組", "Untitled Show", "Chương trình chưa đặt tên") }
    var untitledEpisode: String { t("無題のエピソード", "Untitled Episode", "Tập chưa đặt tên") }

    func resolvedEpisodeTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled Episode" { return untitledEpisode }
        return trimmed
    }

    // MARK: - Help

    var helpVersionFormat: String { t("バージョン %@ (%@)", "Version %@ (%@)", "Phiên bản %@ (%@)") }

    var helpTAddTitle: String { t("番組を追加する", "Add a show", "Thêm chương trình") }
    var helpTAdd1: String { t("⋯ の「\(addShow)」をタップ", "Tap \"\(addShow)\" in ⋯", "Chạm \"\(addShow)\" trong ⋯") }
    var helpTAdd2: String { t("番組名かムードで探す", "Search by name or mood", "Tìm theo tên hoặc tâm trạng") }
    var helpTAdd3: String { t("結果をタップして追加", "Tap a result to add it", "Chạm kết quả để thêm") }
    var helpTRssTitle: String { t("RSS で追加する", "Add by RSS", "Thêm bằng RSS") }
    var helpTRss1: String { t("番組の追加画面で RSS の URL を入力", "Enter the RSS URL on the add screen", "Nhập URL RSS ở màn hình thêm") }
    var helpTRss2: String { t("Safari の共有から osmPod を選んでも取り込める", "Or choose osmPod from Share in Safari", "Hoặc chọn osmPod từ Chia sẻ trong Safari") }
    var helpTAiTitle: String { t("Google AI で番組を探す", "Find shows with Google AI", "Tìm chương trình bằng Google AI") }
    var helpTAi1: String { t("番組の追加画面から Google AI で探す", "Search with Google AI from the add screen", "Tìm bằng Google AI từ màn hình thêm") }
    var helpTAi2: String { t("提案された RSS の URL をコピー", "Copy the suggested RSS URLs", "Sao chép các URL RSS được đề xuất") }
    var helpTAi3: String { t("クリップボードから取り込む", "Import from the clipboard", "Nhập từ bộ nhớ tạm") }
    var helpTFolderTitle: String { t("フォルダで整理する", "Organize with folders", "Sắp xếp bằng thư mục") }
    var helpTFolder1: String { t("⋯ の「\(createFolder)」をタップ", "Tap \"\(createFolder)\" in ⋯", "Chạm \"\(createFolder)\" trong ⋯") }
    var helpTFolder2: String { t("番組をドラッグして並べ替える", "Drag shows to reorder", "Kéo chương trình để sắp xếp") }
    var helpTSortTitle: String { t("並びを変える", "Change the order", "Đổi thứ tự") }
    var helpTSort1: String { t("ツールバーの並び替えメニューをタップ", "Tap the sort menu in the toolbar", "Chạm menu sắp xếp trên thanh công cụ") }
    var helpTSearchTitle: String { t("エピソードを探す", "Find an episode", "Tìm tập") }
    var helpTSearch1: String { t("画面上部の検索バーに入力", "Type in the search bar at the top", "Nhập vào thanh tìm kiếm ở trên cùng") }
    var helpTPlayTitle: String { t("再生画面を開く", "Open the player", "Mở trình phát") }
    var helpTPlay1: String { t("再生中に画面下のミニプレーヤーをタップ", "While playing, tap the mini player at the bottom", "Khi đang phát, chạm trình phát mini ở dưới cùng") }
    var helpTRandomTitle: String { t("おまかせで再生する", "Play at random", "Phát ngẫu nhiên") }
    var helpTRandom1: String { t("タスクバーのシャッフルをタップ", "Tap shuffle in the task bar", "Chạm trộn bài trên thanh tác vụ") }
    var helpTRandom2: String { t("除く番組は再生オプションで選ぶ", "Choose excluded shows in the playback options", "Chọn chương trình loại trừ trong tùy chọn phát") }
    var helpTShakeTitle: String { t("聞き直す", "Listen again", "Nghe lại") }
    var helpTShake1: String { t("端末を振ると巻き戻す", "Shake the device to rewind", "Lắc máy để tua lại") }
    var helpTShake2: String { t("秒数は再生オプションで選ぶ", "Choose the seconds in the playback options", "Chọn số giây trong tùy chọn phát") }
    var helpTBackupTitle: String { t("ライブラリを書き出す・取り込む", "Export or import your library", "Xuất hoặc nhập thư viện") }
    var helpTBackup1: String { t("「\(settings)」の「\(dataManagementGroup)」を開く", "Open \"\(dataManagementGroup)\" in \"\(settings)\"", "Mở \"\(dataManagementGroup)\" trong \"\(settings)\"") }
    var helpTPlanTitle: String { t("プランを確かめる", "Check your plan", "Kiểm tra gói") }
    var helpTPlan1: String { t("⋯ の「\(planManagementMenu)」をタップ", "Tap \"\(planManagementMenu)\" in ⋯", "Chạm \"\(planManagementMenu)\" trong ⋯") }
    var helpIntro: String { t("ポッドキャストをひとつのライブラリで聴くアプリです。", "Listen to your podcasts in one library.", "Nghe podcast trong một thư viện.") }
    var settingsGroupDisplay: String { t("表示と操作", "Display and controls", "Hiển thị và thao tác") }
    var settingsGroupPlayback: String { t("再生とデータ", "Playback and data", "Phát và dữ liệu") }








    // MARK: - Settings

    var updateShowMetadata: String { t("番組情報を更新", "Update Show Information", "Cập nhật thông tin chương trình") }
    var shakeRewindDuration: String { t("シェイクで巻き戻す時間", "Shake to Rewind Duration", "Thời gian tua lại khi lắc") }
    var dataManagement: String { t("データの管理", "Data Management", "Quản lý dữ liệu") }
    var shakeRewindFooter: String {
        t(
            "端末を振ると、再生位置が指定した秒数だけ戻ります。",
            "Shaking the device rewinds playback by the specified number of seconds.",
            "Lắc thiết bị sẽ tua lại theo số giây đã chỉ định."
        )
    }
    var dataManagementFooter: String {
        t(
            "バックアップのエクスポート、リストアのインポート、一括削除が行えます。",
            "Export backups, import restores, and delete items in bulk.",
            "Xuất bản sao lưu, nhập để khôi phục và xóa hàng loạt."
        )
    }
    var playbackOptions: String { t("再生オプション", "Playback Options", "Tùy chọn phát") }
    var playbackOptionsFooter: String {
        t(
            "シェイクでの巻き戻し、再生済みエピソードの扱い、自動再生をまとめて設定できます。",
            "Adjust shake-to-rewind, played episode handling, and auto-play in one place.",
            "Điều chỉnh tua lại khi lắc, cách xử lý tập đã nghe và tự động phát ở một nơi."
        )
    }
    var dataManagementGroup: String { t("データ管理", "Data Management", "Quản lý dữ liệu") }
    var dataManagementGroupFooter: String {
        t(
            "iCloud同期とバックアップの管理をまとめて確認できます。",
            "Manage iCloud sync and backups in one place.",
            "Quản lý đồng bộ iCloud và sao lưu ở một nơi."
        )
    }
    var refreshResultTitle: String { t("更新結果", "Update Result", "Kết quả cập nhật") }
    var rewindSeconds: String { t("巻き戻す秒数", "Rewind Seconds", "Giây tua lại") }
    var languageSection: String { t("言語", "Language", "Ngôn ngữ") }
    var languageFooter: String { t("アプリの表示言語を変更します。", "Changes the display language of the app.", "Thay đổi ngôn ngữ hiển thị của ứng dụng.") }

    var dateFormatSection: String { t("日付表示", "Date Format", "Định dạng ngày") }
    var dateFormatFooter: String {
        t(
            "日付の表示形式を変更します。",
            "Changes how dates are displayed.",
            "Thay đổi cách hiển thị ngày."
        )
    }

    func secondsLabel(_ n: Int) -> String { t("\(n)秒", "\(n) sec", "\(n) giây") }

    func refreshResultMessage(shows: Int, updated: Int, added: Int, failed: Int) -> String {
        t(
            "番組: \(shows)件を更新\nエピソード更新: \(updated)件\nエピソード追加: \(added)件\n失敗: \(failed)件",
            "Shows: \(shows) updated\nEpisodes updated: \(updated)\nEpisodes added: \(added)\nFailed: \(failed)",
            "Chương trình: \(shows) đã cập nhật\nTập cập nhật: \(updated)\nTập thêm mới: \(added)\nThất bại: \(failed)"
        )
    }

    // MARK: - Show Management

    var showManagementButton: String { t("登録済みの番組を管理", "Manage Registered Shows", "Quản lý chương trình đã đăng ký") }
    var showManagementButtonFooter: String {
        t(
            "登録されている番組の一覧・重複の統合・削除ができます。",
            "View all registered shows, merge duplicates, and delete shows.",
            "Xem danh sách, gộp trùng lặp và xóa chương trình."
        )
    }
    var showManagementTitle: String { t("番組の管理", "Manage Shows", "Quản lý chương trình") }
    var showManagementDuplicateNotice: String { t("重複タイトルあり", "Duplicate Titles Found", "Có tiêu đề trùng lặp") }
    func showManagementDuplicateCount(_ n: Int) -> String {
        t(
            "同じタイトルの番組が \(n) 件あります。「重複を統合」で1つにまとめられます。",
            "\(n) shows share the same title. Use \"Merge Duplicates\" to combine them into one.",
            "\(n) chương trình trùng tiêu đề. Dùng \"Gộp trùng lặp\" để gộp thành một."
        )
    }
    func showManagementEpisodeCount(_ n: Int) -> String {
        t("\(n)件のエピソード", "\(n) episodes", "\(n) tập")
    }
    func showManagementDeleteConfirm(_ title: String) -> String {
        t(
            "「\(title)」を削除します。配下のエピソードもすべて削除されます。この操作は取り消せません。",
            "Delete \"\(title)\"? All its episodes will also be deleted. This cannot be undone.",
            "Xóa \"\(title)\"? Tất cả tập của nó sẽ bị xóa. Không thể hoàn tác."
        )
    }
    var showManagementNoShows: String {
        t("登録された番組がありません", "No shows registered", "Không có chương trình nào")
    }
    var showManagementMergeButton: String { t("重複を統合", "Merge Duplicates", "Gộp trùng lặp") }
    var showManagementMergeAllButton: String { t("すべての重複を統合", "Merge All Duplicates", "Gộp tất cả trùng lặp") }
    var showManagementMergeResultTitle: String { t("統合完了", "Merge Complete", "Gộp xong") }
    func showManagementMergeGroupConfirm(_ title: String) -> String {
        t(
            "「\(title)」の重複を1つにまとめます。エピソードは統合され、同じ内容の重複エピソードは削除されます。",
            "Merge duplicate entries for \"\(title)\" into one show. Episodes will be combined and identical duplicates removed.",
            "Gộp các mục trùng \"\(title)\" thành một chương trình. Các tập trùng sẽ bị xóa."
        )
    }
    var showManagementMergeAllConfirm: String {
        t(
            "同じタイトルの番組をすべて1つずつにまとめます。エピソードは統合され、同じ内容の重複エピソードは削除されます。",
            "Merge every duplicate show title into a single show. Episodes will be combined and identical duplicates removed.",
            "Gộp mọi chương trình trùng tiêu đề. Các tập trùng sẽ bị xóa."
        )
    }
    func showManagementMergeResult(_ kept: String, removedShows: Int, moved: Int, removedEpisodes: Int) -> String {
        t(
            "「\(kept)」に統合しました（番組 \(removedShows) 件削除、エピソード \(moved) 件追加、重複 \(removedEpisodes) 件削除）。",
            "Merged into \"\(kept)\" (removed \(removedShows) shows, added \(moved) episodes, deleted \(removedEpisodes) duplicate episodes).",
            "Đã gộp vào \"\(kept)\" (xóa \(removedShows) chương trình, thêm \(moved) tập, xóa \(removedEpisodes) tập trùng)."
        )
    }
    func showManagementMergeAllResult(_ groupCount: Int) -> String {
        t(
            "\(groupCount) グループの重複を統合しました。",
            "Merged duplicates in \(groupCount) groups.",
            "Đã gộp trùng lặp trong \(groupCount) nhóm."
        )
    }
    var showManagementDuplicateGroupsSection: String {
        t("重複している番組", "Duplicate Shows", "Chương trình trùng lặp")
    }
    func showManagementRegisteredAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let formatted = formatter.string(from: date)
        return t("登録: \(formatted)", "Added: \(formatted)", "Đăng ký: \(formatted)")
    }
    func showManagementFeedSource(_ url: String) -> String {
        t("ソース: \(url)", "Source: \(url)", "Nguồn: \(url)")
    }
    func showsSectionWithCount(_ count: Int) -> String {
        t(
            "番組（すべての登録） (\(count))",
            "Shows (All) (\(count))",
            "Chương trình (Tất cả) (\(count))"
        )
    }
    func showManagementMergeFailed(_ detail: String) -> String {
        t(
            "統合に失敗しました: \(detail)",
            "Merge failed: \(detail)",
            "Gộp thất bại: \(detail)"
        )
    }
    var showManagementDuplicateRowHint: String {
        t("同じタイトルの番組があります", "This show has duplicate titles", "Chương trình này trùng tiêu đề")
    }

    // MARK: - Data Management

    var exportSelected: String { t("選択項目をエクスポート", "Export Selected", "Xuất đã chọn") }
    var importJSON: String { t("JSON をインポート", "Import JSON", "Nhập JSON") }
    var fetchingFeeds: String { t("フィードを取得しています…", "Fetching feeds…", "Đang tải nguồn...") }
    var deleteFoldersBulk: String { t("フォルダを一括削除", "Delete Folders", "Xóa thư mục") }
    var resetToPurchaseState: String { t("購入状態に戻す", "Reset to Factory", "Đặt lại về ban đầu") }
    var resetToPurchaseStateMessage: String {
        t(
            "ライブラリ、ダウンロード、取込ファイル、ファイルブックマーク、画像キャッシュ、共有一時データ、対象設定を削除します。iCloudの選択をオンにした場合はクラウド同期データも削除します。この操作は取り消せません。",
            "This deletes the library, downloads, imported files, file bookmarks, image cache, share temporary data, and app preferences. If the iCloud option is on, cloud sync data is also deleted. This cannot be undone.",
            "Thao tác này xóa thư viện, tệp tải/nhập, bookmark tệp, bộ nhớ đệm ảnh, dữ liệu chia sẻ tạm và cài đặt app. Nếu bật tùy chọn iCloud, dữ liệu đồng bộ đám mây cũng bị xóa. Không thể hoàn tác."
        )
    }
    var dataManagementDeleteFooter: String {
        t(
            "フォルダ削除は配下も対象です。Factory Resetは端末データを消去します。クラウド同期データの削除は上のスイッチで選べます。",
            "Deleting a folder also deletes its subfolders. Factory Reset erases on-device data; use the switch above to choose whether to delete cloud sync data.",
            "Xóa thư mục cũng xóa thư mục con. Factory Reset xóa dữ liệu trên thiết bị; dùng công tắc trên để chọn xóa dữ liệu đồng bộ đám mây."
        )
    }
    var foldersSection: String { t("フォルダ", "Folders", "Thư mục") }
    var showsSection: String { t("番組（すべての登録）", "Shows (All)", "Chương trình (Tất cả)") }
    var confirmDelete: String { t("削除の確認", "Confirm Delete", "Xác nhận xóa") }

    func deleteFolderConfirm(_ n: Int) -> String {
        t("選択した \(n) 件のフォルダを削除します。", "Delete \(n) selected folder(s).", "Xóa \(n) thư mục đã chọn.")
    }

    var iCloudSyncDeletionRiskNote: String {
        t(
            "iCloud 同期が有効です。削除前の古いデータが残る他の端末が同期すると、削除した内容が復活することがあります。心配な場合は他の端末でも同期してから削除してください。",
            "iCloud sync is on. If another device still has the older data, syncing it later may bring the deleted items back. If that matters, sync your other devices first.",
            "Đồng bộ iCloud đang bật. Nếu thiết bị khác còn dữ liệu cũ, việc đồng bộ sau đó có thể làm mục đã xóa xuất hiện lại. Nếu cần, hãy đồng bộ các thiết bị khác trước."
        )
    }

    // MARK: - Cloud Sync

    var cloudSync: String { t("iCloud 同期", "iCloud Sync", "Đồng bộ iCloud") }
    var cloudSyncSectionFooter: String {
        t(
            "iCloud を使って複数端末でデータを自動同期できます。",
            "Automatically sync data across devices using iCloud.",
            "Tự động đồng bộ dữ liệu qua các thiết bị bằng iCloud."
        )
    }
    var cloudSyncEnable: String { t("iCloud 同期", "iCloud Sync", "Đồng bộ iCloud") }
    var cloudSyncEnableFooter: String {
        t(
            "同じ Apple ID でサインインした iPhone・iPad 間で、番組・フォルダ・再生状態を自動的に同期します。",
            "Automatically syncs shows, folders, and playback state between iPhone and iPad signed in with the same Apple ID.",
            "Tự động đồng bộ chương trình, thư mục và trạng thái phát giữa iPhone và iPad đăng nhập cùng Apple ID."
        )
    }
    var cloudSyncUnavailable: String {
        t(
            "iCloud が利用できません。設定アプリで iCloud にサインインしてください。",
            "iCloud is not available. Please sign in to iCloud in the Settings app.",
            "iCloud không khả dụng. Vui lòng đăng nhập iCloud trong ứng dụng Cài đặt."
        )
    }
    var cloudSyncLastSync: String { t("最終同期", "Last Synced", "Đồng bộ lần cuối") }
    var cloudSyncNeverSynced: String { t("まだ同期されていません", "Not yet synced", "Chưa được đồng bộ") }
    var cloudSyncNow: String { t("今すぐ同期", "Sync Now", "Đồng bộ ngay") }
    var cloudSyncFooter: String {
        t(
            "アプリが起動・復帰したときに自動で確認し、バックグラウンドに移行したときにアップロードします。",
            "Automatically checks on launch and foreground, and uploads when moving to the background.",
            "Tự động kiểm tra khi khởi động và khi trở về nền trước, tải lên khi chuyển sang nền sau."
        )
    }

    // MARK: - Add Show

    var addShowMethodSection: String { t("追加方法", "How to Add", "Cách thêm") }
    var addShowMethodInApp: String { t("アプリ内で探す", "Search in App", "Tìm trong app") }
    var addShowMethodGoogleAI: String { t("Google AIで探す", "Search with Google AI", "Tìm bằng Google AI") }
    var addShowMethodDirectRSS: String { t("RSSを直接入力", "Enter RSS Directly", "Nhập RSS trực tiếp") }
    var addShowMethodDirectRSSFooter: String {
        t(
            "iTunesにない番組や、すでにRSS URLがわかっている場合に使います。",
            "Use when the show isn't on iTunes or you already have the RSS URL.",
            "Dùng khi chương trình không có trên iTunes hoặc bạn đã có URL RSS."
        )
    }
    var addShowMethodLocalFiles: String { t("ファイルを読み込む", "Import Files", "Nhập tệp") }
    var localFilesShowTitle: String { t("ローカルファイル", "Local Files", "Tệp cục bộ") }
    var localFilesFolderButton: String { t("フォルダを番組として登録", "Register Folder as Show", "Đăng ký thư mục làm chương trình") }
    var localFilesPickerButton: String { t("ファイルを個別に選択", "Select Individual Files", "Chọn tệp riêng lẻ") }
    var localFilesNoAudioFound: String { t("音声ファイルが見つかりませんでした", "No audio files found in folder", "Không tìm thấy tệp âm thanh trong thư mục") }
    var localFilesFooter: String {
        t(
            "「フォルダを番組として登録」: 端末内のフォルダなら音声ファイルを1つ選ぶか、フォルダ自体を選べます。Dropboxなどクラウドの場合は、フォルダ内で「…」→「選択」→「すべてを選択」→「開く」で全ファイルを選んでください。ファイルはコピーされず、再生時に元の場所からアクセスします。",
            "\"Register Folder as Show\": For on-device folders, pick any one audio file or the folder itself. For Dropbox and other cloud storage, open the folder, tap \"…\" → \"Select\" → \"Select All\", then \"Open\". Files are not copied — accessed at playback time.",
            "\"Đăng ký thư mục làm chương trình\": Với thư mục trên thiết bị, chọn một tệp âm thanh hoặc thư mục. Với Dropbox, nhấn \"…\" → \"Chọn\" → \"Chọn tất cả\" → \"Mở\". Tệp không sao chép."
        )
    }
    func localFilesImportedCount(_ imported: Int, failed: Int) -> String {
        if failed == 0 {
            return t("\(imported)件を読み込みました", "\(imported) file(s) imported", "Đã nhập \(imported) tệp")
        }
        return t(
            "\(imported)件を読み込みました（\(failed)件失敗）",
            "\(imported) imported, \(failed) failed",
            "Đã nhập \(imported) tệp (\(failed) thất bại)"
        )
    }
    var searchByShowName: String { t("番組名から検索して追加", "Search by Show Name to Add", "Tìm kiếm theo tên để thêm") }
    var discoverShows: String { t("番組を見つける", "Discover Shows", "Khám phá chương trình") }
    var discoverShowsFooter: String {
        t(
            "番組名・キーワード・ムードから検索。タップで最新エピソードをプレビューしてから追加できます。",
            "Search by show name, topic, or mood. Tap a result to preview the latest episode before adding.",
            "Tìm theo tên, chủ đề hoặc tâm trạng. Nhấn để xem trước tập mới nhất rồi thêm."
        )
    }
    var discoverAdvancedSection: String { t("その他", "More Options", "Tùy chọn khác") }
    var discoverAdvancedFooter: String {
        t(
            "iTunesにない番組はRSS URLを直接入力するか、Google AIで探してクリップボードから取り込めます。",
            "Shows not on iTunes? Paste an RSS URL directly, or use Google AI and import from the clipboard.",
            "Không có trên iTunes? Dán URL RSS hoặc dùng Google AI và nhập từ clipboard."
        )
    }
    var discoverSearchPlaceholder: String {
        t("番組名・キーワード", "Show name or topic", "Tên hoặc chủ đề")
    }
    var discoverSearchFooter: String {
        t(
            "例：「英語 初心者」「ビジネス」「真夜中」など、聴きたいイメージで検索できます。",
            "Try topics like \"beginner English,\" \"business,\" or \"late night.\"",
            "Thử \"tiếng Anh cơ bản,\" \"kinh doanh,\" \"đêm khuya,\" v.v."
        )
    }
    var discoverMoodsSection: String { t("ムードから探す", "Browse by Mood", "Theo tâm trạng") }
    var discoverMoodEnglish: String { t("英語", "English", "Tiếng Anh") }
    var discoverMoodBusiness: String { t("ビジネス", "Business", "Kinh doanh") }
    var discoverMoodNews: String { t("ニュース", "News", "Tin tức") }
    var discoverMoodComedy: String { t("お笑い", "Comedy", "Hài hước") }
    var discoverMoodTrueCrime: String { t("ミステリー", "True Crime", "Tội phạm") }
    var discoverMoodRelax: String { t("リラックス", "Relax", "Thư giãn") }
    var discoverTodayPick: String { t("今日の1本", "Today's Pick", "Gợi ý hôm nay") }
    var discoverAnotherPick: String { t("別の番組", "Another", "Khác") }
    var discoverPreviewShow: String { t("プレビュー", "Preview", "Xem trước") }
    var discoverPreviewTitle: String { t("番組プレビュー", "Show Preview", "Xem trước chương trình") }
    var discoverLatestEpisode: String { t("最新エピソード", "Latest Episode", "Tập mới nhất") }
    var discoverAddShow: String { t("この番組を追加", "Add This Show", "Thêm chương trình") }
    var discoverAddingShow: String { t("追加中…", "Adding…", "Đang thêm…") }
    var discoverRelatedShows: String { t("似た番組", "Similar Shows", "Chương trình tương tự") }
    var shareImportTitle: String { t("共有から取り込む", "Import from Share", "Nhập từ Chia sẻ") }
    var shareImportFooter: String {
        t(
            "Safariなどで「共有」→ osmPod を選ぶと、RSSのURLをまとめて追加できます。初回は共有シートの「編集」で osmPod をオンにしてください（App Group の設定は不要です）。",
            "In Safari, tap Share → osmPod to import RSS URLs. On first use, enable osmPod in the Share sheet’s Edit list (no App Group setup required).",
            "Trong Safari, Chia sẻ → osmPod để nhập URL RSS. Lần đầu bật osmPod trong Chỉnh sửa (không cần App Group)."
        )
    }
    var shareImportAdd: String { t("追加", "Add", "Thêm") }
    var discoverAlreadyRegistered: String { t("登録済み", "Already Added", "Đã thêm") }
    var discoverLoadingPreview: String { t("エピソードを読み込み中…", "Loading episode…", "Đang tải tập…") }
    var discoverNoEpisodePreview: String {
        t("エピソード情報を取得できませんでした", "Could not load episode info", "Không tải được thông tin tập")
    }
    var discoverScanClipboard: String { t("クリップボードを読み取る", "Read Clipboard", "Đọc clipboard") }
    var discoverNoURLsInClipboard: String {
        t("クリップボードにURLが見つかりません", "No URLs found on clipboard", "Không tìm thấy URL trên clipboard")
    }
    var discoverBatchImportTitle: String { t("RSSをまとめて取り込む", "Import RSS URLs", "Nhập nhiều URL RSS") }
    var discoverBatchImportFooter: String {
        t(
            "ボタンを押したときだけクリップボードを読み取ります。URLを抽出した後、RSS取得先を確認してから通信します。",
            "The clipboard is read only when you tap the button. After URLs are extracted, you confirm the RSS destinations before any connection.",
            "Clipboard chỉ được đọc khi bạn nhấn nút. Sau khi trích xuất URL, bạn xác nhận đích RSS trước khi kết nối."
        )
    }
    var discoverLoadingFeeds: String { t("フィードを確認中…", "Checking feeds…", "Đang kiểm tra nguồn…") }
    var discoverRSSFetchConfirmTitle: String {
        t("RSS取得先の確認", "Confirm RSS Connections", "Xác nhận kết nối RSS")
    }
    var discoverRSSFetchConfirmButton: String {
        t("接続して取得", "Connect and Fetch", "Kết nối và tải")
    }
    func discoverRSSFetchConfirmMessage(urls: [String]) -> String {
        let destinations = urls.prefix(8).joined(separator: "\n")
        let remainder = max(0, urls.count - 8)
        let suffix = remainder > 0 ? t("\nほか \(remainder) 件", "\nand \(remainder) more", "\nvà \(remainder) URL khác") : ""
        return t(
            "次のURLへ直接接続し、番組名・画像URLなどのRSS情報を取得します。接続先にはIPアドレス等が伝わる場合があります。よろしいですか？\n\n\(destinations)\(suffix)",
            "osmPod will connect directly to these URLs and fetch RSS data such as show titles and artwork URLs. The destinations may receive data such as your IP address. Continue?\n\n\(destinations)\(suffix)",
            "osmPod sẽ kết nối trực tiếp đến các URL sau và tải dữ liệu RSS như tên chương trình và URL ảnh. Máy chủ đích có thể nhận dữ liệu như địa chỉ IP. Tiếp tục?\n\n\(destinations)\(suffix)"
        )
    }
    func discoverImportSelected(_ count: Int) -> String {
        t("選択した \(count) 件を追加", "Add \(count) Selected", "Thêm \(count) đã chọn")
    }
    var discoverWithAIButton: String { t("Google AIで検索する", "Search with Google AI", "Tìm bằng Google AI") }
    var discoverWithAI: String { t("番組発見AI", "Podcast Discovery AI", "AI Khám phá Podcast") }
    var discoverWithAIWelcome: String {
        t(
            "Googleに聴きたいジャンルや話題を伝えると、ポッドキャスト番組を提案してくれます。RSSのURLをコピーして、下の取り込み機能で追加できます。",
            "Tell Google AI what you want to listen to. It'll suggest podcasts. Copy the RSS URLs and import them below.",
            "Hãy hỏi Google AI về chủ đề muốn nghe. Sao chép URL RSS và nhập bên dưới."
        )
    }
    var discoverWithAIQueryLabel: String { t("聴きたい内容（任意）", "What to listen to (optional)", "Chủ đề muốn nghe (tùy chọn)") }
    var discoverWithAIPlaceholder: String {
        t("例：ベトナム情報を優しく教えてくれる番組", "e.g. Easy English learning podcasts", "Vd: Podcast về thông tin Việt Nam dễ hiểu")
    }
    func discoverWithAIQuery(topic: String) -> String {
        if topic.isEmpty {
            return t(
                "おすすめのポッドキャスト番組とそれぞれのRSSフィードURL（https://で始まるURL）を3件教えてください",
                "Please list 3 recommended podcasts with their RSS feed URLs (starting with https://)",
                "Vui lòng liệt kê 3 podcast được đề xuất kèm URL RSS (bắt đầu bằng https://)"
            )
        }
        return t(
            "「\(topic)」を聴けるポッドキャスト番組とそれぞれのRSSフィードURL（https://で始まるURL）を3件教えてください",
            "Please list 3 podcasts about \"\(topic)\" with their RSS feed URLs (starting with https://)",
            "Vui lòng liệt kê 3 podcast về \"\(topic)\" kèm URL RSS (bắt đầu bằng https://)"
        )
    }
    var discoverWithAIFooter: String {
        t(
            "SafariでGoogle AIが開きます。番組を見つけたらRSSのURLをコピーしてください。",
            "Google AI opens in Safari. When you find a show, copy its RSS URL.",
            "Google AI mở trong Safari. Tìm thấy chương trình, sao chép URL RSS."
        )
    }
    var sendToGoogleConfirmTitle: String {
        t("外部サービスへの送信確認", "Confirm Sending to Google", "Xác nhận gửi đến Google")
    }
    var sendToGoogleConfirmSend: String { t("送信する", "Send", "Gửi") }
    func sendToGoogleConfirmMessage(topic: String) -> String {
        if topic.isEmpty {
            return t(
                "Safariを開き、Google LLCのGoogle検索（AIモード）へ「おすすめ番組とRSS URLを3件」という定型文を送信します。入力した話題は送信されませんが、Google側でIPアドレス、端末・ブラウザ情報、Cookieやアカウント情報等が処理され、検索履歴に保存される場合があります。目的は番組候補の提案です。続けますか？",
                "Safari will send a fixed request—“3 recommended podcasts and RSS URLs”—to Google Search (AI Mode), operated by Google LLC. No topic you typed is sent, but Google may process your IP address, device/browser data, cookies or account data, and may retain the query in search history. The purpose is to suggest podcasts. Continue?",
                "Safari sẽ gửi yêu cầu cố định “3 podcast đề xuất và URL RSS” đến Google Search (Chế độ AI) của Google LLC. Không có chủ đề bạn nhập được gửi, nhưng Google có thể xử lý địa chỉ IP, dữ liệu thiết bị/trình duyệt, cookie hoặc tài khoản và có thể lưu truy vấn vào lịch sử tìm kiếm. Mục đích là gợi ý podcast. Tiếp tục?"
            )
        }
        return t(
            "Safariを開き、Google LLCのGoogle検索（AIモード）へ、あなたが入力した話題「\(topic)」を含む番組提案依頼を送信します。話題には氏名、健康、趣味などの個人情報・センシティブ情報が含まれる可能性があります。Google側でIPアドレス、端末・ブラウザ情報、Cookieやアカウント情報等が処理され、検索履歴に保存される場合があります。目的は話題に合う番組候補の提案です。続けますか？",
            "Safari will send a podcast recommendation request containing your topic—“\(topic)”—to Google Search (AI Mode), operated by Google LLC. Your topic may contain personal or sensitive information such as names, health details, or interests. Google may process your IP address, device/browser data, cookies or account data, and may retain the query in search history. The purpose is to suggest podcasts matching your topic. Continue?",
            "Safari sẽ gửi yêu cầu gợi ý podcast có chủ đề bạn nhập—“\(topic)”—đến Google Search (Chế độ AI) của Google LLC. Chủ đề có thể chứa thông tin cá nhân hoặc nhạy cảm như tên, sức khỏe hoặc sở thích. Google có thể xử lý địa chỉ IP, dữ liệu thiết bị/trình duyệt, cookie hoặc tài khoản và có thể lưu truy vấn vào lịch sử. Mục đích là gợi ý podcast phù hợp. Tiếp tục?"
        )
    }
    var pasteToRSSInput: String { t("RSS入力へ貼り付け", "Paste into RSS Input", "Dán vào nhập RSS") }
    var pasteToRSSInputFooter: String {
        t(
            "SafariでRSSのURLを1件コピーしたあと、このボタンで「RSSを直接入力」に貼り付けます。",
            "After copying one RSS URL in Safari, tap to paste it into Enter RSS Directly.",
            "Sau khi sao chép một URL RSS trong Safari, nhấn để dán vào Nhập RSS trực tiếp."
        )
    }
    var useThisURL: String { t("このURLを登録する", "Use this URL", "Dùng URL này") }
    var rssFeed: String { t("RSSフィード", "RSS Feed", "Nguồn RSS") }
    var showInfoOptional: String { t("番組情報（任意）", "Show Info (Optional)", "Thông tin chương trình (Tùy chọn)") }
    var showInfoFooter: String {
        t(
            "未入力の項目はフィードから自動取得します。",
            "Empty fields will be fetched from the feed.",
            "Các trường trống sẽ được lấy từ nguồn."
        )
    }
    var titlePlaceholder: String { t("タイトル", "Title", "Tiêu đề") }
    var artworkURLPlaceholder: String { t("アートワーク画像URL", "Artwork Image URL", "URL ảnh nghệ thuật") }
    var targetFolder: String { t("登録先フォルダ", "Target Folder", "Thư mục đích") }
    var invalidURLError: String {
        t(
            "有効なRSSフィードURLを入力してください。",
            "Please enter a valid RSS feed URL.",
            "Vui lòng nhập URL nguồn RSS hợp lệ."
        )
    }

    // MARK: - Podcast Search

    var searchPodcast: String { t("番組を検索", "Search Shows", "Tìm kiếm chương trình") }
    var showNamePlaceholder: String { t("番組名を入力", "Enter show name", "Nhập tên chương trình") }
    var registering: String { t("登録中...", "Registering...", "Đang đăng ký...") }
    var noSearchResults: String { t("検索結果がありません", "No results found", "Không tìm thấy kết quả") }
    func searchResultsCount(_ n: Int) -> String {
        t("検索結果 \(n)件", "Results: \(n)", "Kết quả: \(n)")
    }

    // MARK: - Folder Edit

    var editFolder: String { t("フォルダを編集", "Edit Folder", "Chỉnh sửa thư mục") }
    var createSubfolder: String { t("サブフォルダを作成", "Create Subfolder", "Tạo thư mục con") }
    var folderName: String { t("フォルダ名", "Folder Name", "Tên thư mục") }
    var parentFolder: String { t("親フォルダ", "Parent Folder", "Thư mục cha") }
    var icon: String { t("アイコン", "Icon", "Biểu tượng") }

    // MARK: - Library Sort Menu

    var sortLabel: String { t("並び替え", "Sort", "Sắp xếp") }
    var foldersAndSubfolders: String { t("フォルダ・サブフォルダ", "Folders & Subfolders", "Thư mục & Thư mục con") }
    var subfoldersSection: String { t("サブフォルダ", "Subfolders", "Thư mục con") }
    var episodes: String { t("エピソード", "Episodes", "Tập") }
    var date: String { t("日付", "Date", "Ngày") }
    var nameLabel: String { t("名前", "Name", "Tên") }
    var moveFolderUp: String { t("上に移動", "Move Up", "Di chuyển lên") }
    var moveFolderDown: String { t("下に移動", "Move Down", "Di chuyển xuống") }
    var rootFolderReorderHint: String {
        t(
            "トップのフォルダは長押しして「上に移動」「下に移動」で並べ替えできます。",
            "Long-press a top-level folder and choose Move Up or Move Down.",
            "Nhấn giữ thư mục gốc rồi chọn Di chuyển lên hoặc xuống."
        )
    }
    var noPublishDate: String { t("公開日未設定", "No publish date", "Chưa có ngày phát") }
    var favorite: String { t("お気に入り", "Favorite", "Yêu thích") }
    var favorited: String { t("お気に入り済み", "Favorited", "Đã yêu thích") }

    // MARK: - Feedback

    var feedback: String { t("フィードバック", "Feedback", "Phản hồi") }
    var hapticFeedback: String { t("触覚フィードバック", "Haptic Feedback", "Phản hồi xúc giác") }
    var hapticIntensityLabel: String { t("強度", "Intensity", "Cường độ") }
    var soundFeedback: String { t("サウンドフィードバック", "Sound Feedback", "Phản hồi âm thanh") }
    var soundVolume: String { t("音量", "Volume", "Âm lượng") }
    var feedbackFooter: String {
        t(
            "ボタン操作時の振動・サウンドを設定します。",
            "Configure vibration and sound for button actions.",
            "Cấu hình rung và âm thanh cho thao tác nút."
        )
    }

    // MARK: - Episode playback state

    var playbackState: String { t("再生状態", "Playback Status", "Trạng thái phát") }
    var markAsPlayed: String { t("再生済みにする", "Mark as Played", "Đánh dấu đã nghe") }
    var markAsUnplayed: String { t("未再生にする", "Mark as Unplayed", "Đánh dấu chưa nghe") }

    // MARK: - Player

    var saveToFolder: String { t("登録先", "Save to", "Lưu vào") }
    var noFolderSelected: String { t("フォルダ未選択", "No folder", "Chưa chọn thư mục") }
    var deleteShowConfirm: String {
        t(
            "この番組をライブラリから削除します。エピソードもすべて削除されます。",
            "Delete this show from your library. All its episodes will also be deleted.",
            "Xóa chương trình này khỏi thư viện. Tất cả tập cũng sẽ bị xóa."
        )
    }

    var downloaded: String { t("ダウンロード済み", "Downloaded", "Đã tải") }
    var download: String { t("ダウンロード", "Download", "Tải xuống") }
    var cloudFilePreparingTitle: String {
        t("クラウドからダウンロード中", "Downloading from Cloud", "Đang tải từ đám mây")
    }
    var cloudFilePreparingIndeterminate: String {
        t("ダウンロード中…", "Downloading…", "Đang tải xuống…")
    }
    var cloudFilePreparingStartingPlayback: String {
        t("再生を開始しています…", "Starting playback…", "Đang bắt đầu phát…")
    }
    var cloudFilePreparingMessage: String {
        t(
            "ファイルを取得しています。完了次第、自動的に再生を開始します。",
            "Fetching the file from cloud storage. Playback will start automatically when ready.",
            "Đang lấy tệp từ đám mây. Phát sẽ tự động bắt đầu khi sẵn sàng."
        )
    }
    func cloudFilePreparingPercent(_ percent: Int) -> String {
        t("\(percent)% 完了", "\(percent)% complete", "\(percent)% hoàn thành")
    }
    var cloudFilePreparationTimeout: String {
        t(
            "クラウドからのファイル取得がタイムアウトしました。ネットワーク接続を確認して、もう一度お試しください。",
            "Timed out while fetching the file from cloud storage. Check your network connection and try again.",
            "Hết thời gian chờ khi lấy tệp từ đám mây. Kiểm tra kết nối mạng và thử lại."
        )
    }
    var cloudFilePreparationUnreadable: String {
        t(
            "クラウド上のファイルを読み取れませんでした。Dropbox アプリでファイルを開いてから、もう一度お試しください。",
            "Could not read the file from cloud storage. Try opening it in the Dropbox app first, then play again.",
            "Không thể đọc tệp từ đám mây. Hãy thử mở tệp trong ứng dụng Dropbox trước, rồi phát lại."
        )
    }
    var repeatPlayback: String { t("リピート再生", "Repeat", "Lặp lại") }

    // MARK: - Playback Settings

    var playbackSettings: String { t("再生設定", "Playback", "Cài đặt phát") }

    // MARK: - Auto Play

    var autoPlaySection: String { t("再生終了後", "After Episode Ends", "Sau khi tập kết thúc") }
    var autoPlayNextEpisodeLabel: String {
        t(
            "別のエピソードを自動再生する",
            "Autoplay next episode",
            "Tự động phát tập tiếp theo"
        )
    }
    var autoPlaySectionFooter: String {
        t(
            "最新エピソードを再生し終えたとき、続けて別のエピソードを自動再生します。",
            "When the latest episode finishes, automatically plays another episode.",
            "Khi tập mới nhất kết thúc, tự động phát tập tiếp theo."
        )
    }
    var autoPlayOrderLabel: String { t("エピソードの選び方", "Episode selection", "Cách chọn tập") }
    var autoPlayExcludedShowsButton: String { t("再生しない番組", "Excluded Shows", "Chương trình không tự động phát") }
    var autoPlayExcludedShowsTitle: String { t("再生しない番組", "Excluded Shows", "Chương trình không tự động phát") }
    var autoPlayExcludedShowsDuplicateHint: String {
        t(
            "同じタイトルの番組が複数あります。統合すると一覧がすっきりします。",
            "Some shows share the same title. Merging them will clean up this list.",
            "Một số chương trình trùng tiêu đề. Gộp lại sẽ gọn danh sách hơn."
        )
    }
    var autoPlayExcludedShowsFooter: String {
        t(
            "チェックした番組は自動再生の対象から除外されます。",
            "Checked shows will be excluded from autoplay.",
            "Các chương trình đã chọn sẽ bị loại khỏi tự động phát."
        )
    }

    // MARK: - Played Episodes Section

    var playedEpisodesSection: String { t("再生済みエピソード", "Played Episodes", "Tập đã nghe") }
    var skipPlayedLabel: String { t("再生スキップ", "Skip Played", "Bỏ qua đã nghe") }
    var hidePlayedLabel: String { t("非表示", "Hide", "Ẩn") }
    var skipPlayedEpisodes: String { t("再生済みエピソードをスキップ", "Skip Played Episodes", "Bỏ qua tập đã nghe") }
    var skipPlayedEpisodesFooter: String {
        t(
            "過去のエピソードを順番に再生するとき、再生済みのエピソードをスキップします。",
            "Skips already-played episodes when playing through a show or folder in sequence.",
            "Bỏ qua các tập đã nghe khi phát tuần tự chương trình hoặc thư mục."
        )
    }

    // MARK: - Library Settings

    var librarySettings: String { t("ライブラリ", "Library", "Thư viện") }
    var hidePlayedEpisodes: String { t("再生済みエピソードを非表示", "Hide Played Episodes", "Ẩn tập đã nghe") }
    var hidePlayedEpisodesFooter: String {
        t(
            "ライブラリのエピソード一覧から、再生済みのエピソードを隠します。",
            "Hides already-played episodes from episode lists in the library.",
            "Ẩn các tập đã nghe khỏi danh sách tập trong thư viện."
        )
    }
    var jumpToEpisodeListTop: String {
        t("エピソードリストの先頭へ", "Go to top of episode list", "Đến đầu danh sách tập")
    }
    var jumpToEpisodeListBottom: String {
        t("エピソードリストの末尾へ", "Go to bottom of episode list", "Đến cuối danh sách tập")
    }
    var noVisibleEpisodes: String {
        t(
            "表示できるエピソードがありません",
            "No episodes to show",
            "Không có tập nào để hiển thị"
        )
    }

    // MARK: - Group / Folder Context Menu

    var episodeList: String { t("エピソード一覧", "Episode List", "Danh sách tập") }
    var removeFromFolder: String { t("フォルダから削除", "Remove from Folder", "Xóa khỏi thư mục") }

    // MARK: - Episode Search

    var noEpisodes: String { t("エピソードがありません", "No Episodes", "Không có tập nào") }
    var noEpisodesDescription: String {
        t(
            "番組を追加するとエピソードが表示されます。",
            "Add a show to see episodes.",
            "Thêm chương trình để xem các tập."
        )
    }
    var searchEpisodes: String { t("エピソードを検索", "Search Episodes", "Tìm kiếm tập") }
    var addToFolder: String { t("フォルダに追加", "Add to Folder", "Thêm vào thư mục") }
    func addCountToFolder(_ n: Int) -> String {
        t("\(n)件を追加", "Add \(n)", "Thêm \(n)")
    }
    func addCountToFolderTitle(_ n: Int) -> String {
        t("\(n)件をフォルダに追加", "Add \(n) to Folder", "Thêm \(n) vào thư mục")
    }

    // MARK: - Plan management

    var planManagementTitle: String { t("プラン管理", "Plan Management", "Quản lý gói") }
    var planCurrentPlanLabel: String { t("現在のプラン", "Current Plan", "Gói hiện tại") }
    var planShowLimitLabel: String { t("番組登録の上限", "Show registration limit", "Giới hạn chương trình") }
    var planFolderLimitLabel: String { t("フォルダ作成の上限", "Folder creation limit", "Giới hạn thư mục") }
    var planUnlimited: String { t("無制限", "Unlimited", "Không giới hạn") }

    func planLimitCountUnit(_ n: Int) -> String {
        t("\(n)件", "\(n)", "\(n)")
    }

    var planFreeShowLimitFooterFormat: String {
        t(
            "FREE プランでは番組を最大 %d 件まで登録できます。PREMIUM にアップグレードすると無制限です。",
            "On the FREE plan you can register up to %d shows. Upgrade to PREMIUM for unlimited shows.",
            "Gói FREE cho phép đăng ký tối đa %d chương trình. Nâng cấp PREMIUM để không giới hạn."
        )
    }

    var planFreeFolderLimitFooterFormat: String {
        t(
            "FREE プランではフォルダを最大 %d 件まで作成できます。PREMIUM にアップグレードすると無制限です。",
            "On the FREE plan you can create up to %d folders. Upgrade to PREMIUM for unlimited folders.",
            "Gói FREE cho phép tạo tối đa %d thư mục. Nâng cấp PREMIUM để không giới hạn."
        )
    }

    var planNoticeTitle: String { t("お知らせ", "Notice", "Thông báo") }
    var planProcessing: String { t("処理中…", "Processing…", "Đang xử lý…") }
    var planUpgradeButton: String { t("PREMIUMにアップグレード", "Upgrade to PREMIUM", "Nâng cấp PREMIUM") }
    var planRestoring: String { t("復元中…", "Restoring…", "Đang khôi phục…") }
    var planRestorePurchases: String { t("購入を復元", "Restore Purchases", "Khôi phục mua hàng") }
    var planPurchaseSuccess: String {
        t(
            "PREMIUM へのアップグレードが完了しました。",
            "Upgrade to PREMIUM completed.",
            "Đã nâng cấp lên PREMIUM."
        )
    }
    var planRestoreSuccess: String {
        t("購入を復元しました。", "Purchases restored.", "Đã khôi phục giao dịch mua.")
    }
    var planRestoreNothingFound: String {
        t(
            "復元できる購入が見つかりませんでした。",
            "No purchases were found to restore.",
            "Không tìm thấy giao dịch để khôi phục."
        )
    }

    var planPurchaseErrorGeneric: String {
        t(
            "購入を完了できませんでした。しばらくしてからもう一度お試しください。",
            "We couldn’t complete the purchase. Please try again in a moment.",
            "Không thể hoàn tất giao dịch. Vui lòng thử lại sau."
        )
    }
    var planPurchaseErrorNetwork: String {
        t(
            "通信エラーのため購入を完了できませんでした。接続を確認してからもう一度お試しください。",
            "We couldn’t complete the purchase due to a network issue. Check your connection and try again.",
            "Không thể hoàn tất giao dịch do lỗi mạng. Kiểm tra kết nối và thử lại."
        )
    }
    var planPurchaseErrorUnavailable: String {
        t(
            "このストアでは購入を利用できない場合があります。App Store の国または地域をご確認ください。",
            "Purchases may be unavailable in your storefront. Check your App Store country or region.",
            "Giao dịch có thể không khả dụng ở cửa hàng của bạn. Kiểm tra quốc gia/khu vực App Store."
        )
    }

    var planDeveloperSectionTitle: String { t("開発者メニュー", "Developer", "Nhà phát triển") }
    var planDeveloperTestPlan: String { t("テスト用プラン", "Test plan", "Gói thử") }
    var planDeveloperFooter: String {
        t(
            "プランを切り替えると登録・フォルダの上限とアイコン表示が変わります。",
            "Switching plans changes registration limits and the plan icon.",
            "Đổi gói sẽ thay đổi giới hạn và biểu tượng gói."
        )
    }
    var planNameFree: String { "FREE" }
    var planNamePremium: String { "PREMIUM" }

    var showRegistrationLimitReached: String {
        t(
            "FREE プランではこれ以上番組を登録できません。プラン管理から PREMIUM にアップグレードしてください。",
            "You’ve reached the show limit on the FREE plan. Upgrade to PREMIUM from Plan Management.",
            "Bạn đã đạt giới hạn chương trình trên gói FREE. Hãy nâng cấp PREMIUM trong Quản lý gói."
        )
    }
    var folderCreationLimitReached: String {
        t(
            "FREE プランではこれ以上フォルダを作成できません。プラン管理から PREMIUM にアップグレードしてください。",
            "You’ve reached the folder limit on the FREE plan. Upgrade to PREMIUM from Plan Management.",
            "Bạn đã đạt giới hạn thư mục trên gói FREE. Hãy nâng cấp PREMIUM trong Quản lý gói."
        )
    }

    // MARK: - Feed Parse Errors

    var feedParseInvalidURL: String {
        t(
            "有効なHTTP/HTTPSのフィードURLを入力してください。",
            "Please enter a valid HTTP/HTTPS feed URL.",
            "Vui lòng nhập URL nguồn HTTP/HTTPS hợp lệ."
        )
    }
    func feedParseHTTPError(_ code: Int) -> String {
        t(
            "フィードの取得に失敗しました（HTTPエラー: \(code)）。",
            "Failed to fetch the feed (HTTP error: \(code)).",
            "Không tải được nguồn (lỗi HTTP: \(code))."
        )
    }
    func feedParseNetworkError(_ message: String) -> String {
        t(
            "ネットワークエラーが発生しました: \(message)",
            "A network error occurred: \(message)",
            "Lỗi mạng: \(message)"
        )
    }
    func feedParseMalformedXML(_ message: String) -> String {
        t(
            "XMLの解析に失敗しました: \(message)",
            "Failed to parse XML: \(message)",
            "Không phân tích được XML: \(message)"
        )
    }
    var feedParseInvalidXML: String {
        t(
            "フィードのXML形式が不正です。",
            "The feed XML format is invalid.",
            "Định dạng XML nguồn không hợp lệ."
        )
    }
    var feedParseMissingChannelTitle: String {
        t(
            "フィードにチャンネルタイトルが含まれていません。",
            "The feed does not include a channel title.",
            "Nguồn không có tiêu đề kênh."
        )
    }

    // MARK: - Download Errors

    var downloadInvalidSourceURL: String {
        t(
            "音声URLが不正なためダウンロードできません。",
            "Cannot download because the audio URL is invalid.",
            "Không thể tải vì URL âm thanh không hợp lệ."
        )
    }

    // MARK: - Purchase Errors

    var purchaseProductNotFound: String {
        t(
            """
            購入商品が見つかりませんでした。
            App Store Connect 側で以下を確認してください:
            1) Product ID が com.osamushikubo.osmPod.upgrade と完全一致
            2) 本アプリ（Bundle ID: com.osamushikubo.osmPod）に紐づく IAP になっている
            3) IAP のステータスが取得可能状態（Draft/Missing Metadata ではない）
            """,
            """
            The purchase product was not found.
            In App Store Connect, verify:
            1) Product ID exactly matches com.osamushikubo.osmPod.upgrade
            2) IAP is linked to this app (Bundle ID: com.osamushikubo.osmPod)
            3) IAP status is available (not Draft/Missing Metadata)
            """,
            """
            Không tìm thấy sản phẩm mua.
            Trong App Store Connect, kiểm tra:
            1) Product ID khớp com.osamushikubo.osmPod.upgrade
            2) IAP thuộc app này (Bundle ID: com.osamushikubo.osmPod)
            3) Trạng thái IAP có thể dùng (không phải Draft/Missing Metadata)
            """
        )
    }
    func purchaseVerificationFailed(_ details: String) -> String {
        t(
            "購入の検証に失敗しました。\(details)",
            "Purchase verification failed. \(details)",
            "Xác minh giao dịch thất bại. \(details)"
        )
    }

    // MARK: - Developer Debug

    var developerModeSection: String { t("開発者向け", "Developer", "Dành cho nhà phát triển") }

    var developerModeEnabledMessage: String {
        t("開発者モードを有効にしました", "Developer mode enabled", "Đã bật chế độ nhà phát triển")
    }

    var developerModeDisabledMessage: String {
        t("開発者モードを無効にしました", "Developer mode disabled", "Đã tắt chế độ nhà phát triển")
    }

    var shareDebugLogButton: String { t("再生ログを共有", "Share Playback Log", "Chia sẻ nhật ký phát") }

    var shareDebugLogFooter: String {
        t(
            "ロック画面の再生表示がおかしいなど、不具合に気づいた時点でこのボタンを押すと、直近数時間分の再生関連ログを書き出して共有できます。",
            "If you notice a playback glitch (e.g. the lock screen showing the wrong play/pause state), tap this to export and share the last few hours of playback-related logs.",
            "Nếu bạn gặp sự cố phát lại (ví dụ màn hình khóa hiển thị sai trạng thái phát/tạm dừng), nhấn nút này để xuất và chia sẻ nhật ký phát lại vài giờ gần nhất."
        )
    }

    var shareDebugLogFailedMessage: String {
        t(
            "ログの書き出しに失敗しました。",
            "Failed to export the log.",
            "Xuất nhật ký thất bại."
        )
    }
}
