import Foundation
import SwiftData

// MARK: - Service

struct FeedParserService: Sendable {

    /// 指定URLのRSSフィードを取得・解析して ParsedFeed を返す。
    /// non-isolated な async 関数はコオペレーティブスレッドプールで実行されるため、
    /// メインスレッドをブロックせずに同期XMLパーサーを安全に呼び出せる。
    func parse(feedURL: URL) async throws -> ParsedFeed {
        guard feedURL.scheme == "http" || feedURL.scheme == "https" else {
            throw FeedParseError.invalidURL
        }

        let data: Data
        do {
            let (fetchedData, response) = try await URLSession.shared.data(from: feedURL)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw FeedParseError.httpError(http.statusCode)
            }
            data = fetchedData
        } catch let error as FeedParseError {
            throw error
        } catch {
            throw FeedParseError.networkError(error)
        }

        return try RSSParserDelegate.parse(data: data)
    }

    /// ParsedFeed.Channel から Show モデルを生成する。
    /// @Model オブジェクトを生成するためメインアクターで実行する。
    @MainActor
    func makeShow(from feed: ParsedFeed, feedURL: URL) -> Show {
        Show(
            title: feed.channel.title,
            feedURL: feedURL.absoluteString,
            artworkURL: feed.channel.artworkURL
        )
    }

    /// ParsedFeed のエピソード群から Episode モデルの配列を生成する。
    /// @Model オブジェクトを生成・関連付けするためメインアクターで実行する。
    /// - Parameter maxCount: 指定時は先頭 N 件のみ（サンプル番組の初期投入など大量フィードの短時間化用）。
    @MainActor
    func makeEpisodes(from feed: ParsedFeed, show: Show, maxCount: Int? = nil) -> [Episode] {
        let items: ArraySlice<ParsedFeed.EpisodeItem>
        if let maxCount {
            items = feed.episodes.prefix(maxCount)[...]
        } else {
            items = feed.episodes[...]
        }
        return items.enumerated().map { index, item in
            Episode(
                number: item.number,
                title: LocalizedStrings.current.resolvedEpisodeTitle(item.title),
                audioURL: item.audioURL,
                artworkURL: item.artworkURL,
                publishedAt: item.publishedAt,
                summary: item.summary,
                sortOrder: index,
                show: show
            )
        }
    }
}

@MainActor
@Observable
final class FeedRefreshService {
    @ObservationIgnored private let parser = FeedParserService()
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var lastStartedAt: Date?

    func refreshIfNeeded(context: ModelContext, minimumInterval: TimeInterval = 30) async {
        if let lastStartedAt, Date().timeIntervalSince(lastStartedAt) < minimumInterval {
            return
        }
        guard !isChecking else { return }
        isChecking = true
        lastStartedAt = Date()
        defer { isChecking = false }

        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let targets = shows.compactMap { show -> (String, URL)? in
            guard let feedURL = URL(string: show.feedURL) else { return nil }
            return (show.feedURL, feedURL)
        }

        // iOS 26 Beta の withTaskGroup に TaskGroup::offer クラッシュがあるため順次取得に変更。
        // 並列化による速度差は通常の番組数では体感できない。
        var parsedResults: [String: ParsedFeed] = [:]
        for (feedURL, url) in targets {
            guard !Task.isCancelled else { break }
            do {
                let feed = try await parser.parse(feedURL: url)
                parsedResults[feedURL] = feed
            } catch {
                // ネットワークエラーや解析失敗は無視して次の番組へ
            }
        }

        // await 後に再フェッチ: サスペンド中に show のフォルト参照が無効化されるため
        let freshShows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        for show in freshShows {
            guard let parsed = parsedResults[show.feedURL] else { continue }
            merge(parsedFeed: parsed, into: show, context: context)
        }
    }

    private func merge(parsedFeed: ParsedFeed, into show: Show, context: ModelContext) {
        let feedURL = show.feedURL
        let existing = (try? context.fetch(
            FetchDescriptor<Episode>(predicate: #Predicate { $0.show.feedURL == feedURL })
        )) ?? []
        var knownURLs = Set(existing.map(\.audioURL))
        let existingPublishedMax = existing.compactMap(\.publishedAt).max()
        var insertedAny = false

        for (index, item) in parsedFeed.episodes.enumerated() {
            guard !knownURLs.contains(item.audioURL) else { continue }
            // audioURL はグローバル unique 制約。他番組の既存エピソードと重複すれば保存エラーになるので挿入しない。
            // #Predicate に struct プロパティを渡す場合もローカル変数に取り出して Value として扱わせる。
            let candidateURL = item.audioURL
            let dupDesc = FetchDescriptor<Episode>(predicate: #Predicate { $0.audioURL == candidateURL })
            if (try? context.fetchCount(dupDesc)) ?? 0 > 0 {
                knownURLs.insert(item.audioURL)
                continue
            }
            let episode = Episode(
                number: item.number,
                title: item.title,
                audioURL: item.audioURL,
                artworkURL: item.artworkURL,
                publishedAt: item.publishedAt,
                summary: item.summary,
                sortOrder: index,
                isNew: shouldMarkAsNew(itemPublishedAt: item.publishedAt, baselinePublishedAt: existingPublishedMax),
                show: show
            )
            context.insert(episode)
            knownURLs.insert(item.audioURL)
            insertedAny = true
        }

        guard insertedAny else { return }
        NewEpisodeIndicatorSync.refreshAll(in: context)
    }

    private func shouldMarkAsNew(itemPublishedAt: Date?, baselinePublishedAt: Date?) -> Bool {
        guard let itemPublishedAt else { return true }
        guard let baselinePublishedAt else { return true }
        return itemPublishedAt > baselinePublishedAt
    }
}

// MARK: - Error

enum FeedParseError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case networkError(Error)
    case malformedXML(Error)
    case invalidXML
    case missingChannelTitle

    var errorDescription: String? {
        let s = LocalizedStrings.current
        switch self {
        case .invalidURL:
            return s.feedParseInvalidURL
        case .httpError(let code):
            return s.feedParseHTTPError(code)
        case .networkError(let error):
            return s.feedParseNetworkError(error.localizedDescription)
        case .malformedXML(let error):
            return s.feedParseMalformedXML(error.localizedDescription)
        case .invalidXML:
            return s.feedParseInvalidXML
        case .missingChannelTitle:
            return s.feedParseMissingChannelTitle
        }
    }
}

// MARK: - XML Parser Delegate (private)

private final class RSSParserDelegate: NSObject, XMLParserDelegate {

    private struct PartialEpisode {
        var title = ""
        var audioURL = ""
        var artworkURL: String?
        var publishedAt: Date?
        var summary = ""
        var number: Int?
    }

    private static let itunesNamespace = "http://www.itunes.com/dtds/podcast-1.0.dtd"

    private var channelTitle: String?
    private var channelArtworkURL: String?

    private var currentText = ""
    private var isInItem = false
    private var isInChannelImage = false

    private var currentEpisode: PartialEpisode?
    private var episodes: [ParsedFeed.EpisodeItem] = []

    private var parseError: Error?

    // MARK: Entry Point

    static func parse(data: Data) throws -> ParsedFeed {
        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true

        let success = parser.parse()

        if let error = delegate.parseError {
            throw FeedParseError.malformedXML(error)
        }
        guard success else {
            if let error = parser.parserError {
                throw FeedParseError.malformedXML(error)
            }
            throw FeedParseError.invalidXML
        }
        guard let title = delegate.channelTitle, !title.isEmpty else {
            throw FeedParseError.missingChannelTitle
        }

        return ParsedFeed(
            channel: .init(title: title, artworkURL: delegate.channelArtworkURL),
            episodes: delegate.episodes
        )
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        let isItunes = namespaceURI == Self.itunesNamespace

        switch elementName {
        case "item" where !isItunes:
            isInItem = true
            currentEpisode = PartialEpisode()

        case "image" where !isInItem && isItunes:
            // <itunes:image href="..."/> — 属性値で直接取得
            if let href = attributeDict["href"], !href.isEmpty {
                channelArtworkURL = href
            }

        case "image" where !isInItem:
            // RSS <image><url>...</url></image> — 子要素で取得
            isInChannelImage = true

        case "enclosure" where isInItem:
            if let url = attributeDict["url"], !url.isEmpty {
                currentEpisode?.audioURL = url
            }

        case "image" where isInItem && isItunes:
            if let href = attributeDict["href"], !href.isEmpty {
                currentEpisode?.artworkURL = href
            }

        case "thumbnail" where isInItem:
            if let url = attributeDict["url"], !url.isEmpty {
                currentEpisode?.artworkURL = url
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName _: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isItunes = namespaceURI == Self.itunesNamespace

        switch elementName {
        case "item" where !isItunes:
            if let ep = currentEpisode, !ep.audioURL.isEmpty {
                episodes.append(ParsedFeed.EpisodeItem(
                    title: ep.title,
                    audioURL: ep.audioURL,
                    artworkURL: ep.artworkURL,
                    publishedAt: ep.publishedAt,
                    summary: ep.summary,
                    number: ep.number
                ))
            }
            currentEpisode = nil
            isInItem = false

        case "image" where !isItunes:
            isInChannelImage = false

        case "title" where !isItunes:
            if isInItem {
                currentEpisode?.title = text
            } else if channelTitle == nil {
                // チャンネルレベルの最初の <title> のみ採用
                channelTitle = text
            }

        case "url" where !isItunes && isInChannelImage:
            if channelArtworkURL == nil {
                channelArtworkURL = text
            }

        case "pubDate" where isInItem:
            currentEpisode?.publishedAt = parseDate(text)

        case "description" where isInItem:
            // <itunes:summary> がある場合はそちらで上書きされるので空の場合のみセット
            if currentEpisode?.summary.isEmpty == true {
                currentEpisode?.summary = text
            }

        case "summary" where isItunes && isInItem:
            currentEpisode?.summary = text

        case "episode" where isItunes && isInItem:
            currentEpisode?.number = Int(text)

        default:
            break
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: Date Parsing

    // static let に DateFormatter（non-Sendable）を持つと Swift 6 の concurrency チェックに
    // 抵触するため、インスタンスごとに生成してスレッド間共有を回避する。
    private let dateFormatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",   // RFC 2822（標準）
        "EEE, dd MMM yyyy HH:mm:ss z",   // RFC 2822（タイムゾーン名）
        "dd MMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd'T'HH:mm:ssZ",         // ISO 8601
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private func parseDate(_ string: String) -> Date? {
        dateFormatters.lazy.compactMap { $0.date(from: string) }.first
    }
}
