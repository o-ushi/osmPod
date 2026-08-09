import Foundation

// MARK: - API Models

struct PodcastSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [PodcastSearchResult]
}

struct PodcastSearchResult: Codable, Identifiable, Sendable, Hashable {
    var id: Int { trackId ?? collectionId ?? 0 }
    let trackId: Int?
    let collectionId: Int?
    let collectionName: String?
    let artistName: String?
    let artworkUrl600: String?
    let feedUrl: String?
    let primaryGenreName: String?
}

// MARK: - Discovery Mood

enum DiscoveryMood: String, CaseIterable, Identifiable {
    case english
    case business
    case news
    case comedy
    case trueCrime
    case relax

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .english: return "globe"
        case .business: return "briefcase"
        case .news: return "newspaper"
        case .comedy: return "face.smiling"
        case .trueCrime: return "magnifyingglass"
        case .relax: return "moon.zzz"
        }
    }

    func label(strings: LocalizedStrings) -> String {
        switch self {
        case .english: return strings.discoverMoodEnglish
        case .business: return strings.discoverMoodBusiness
        case .news: return strings.discoverMoodNews
        case .comedy: return strings.discoverMoodComedy
        case .trueCrime: return strings.discoverMoodTrueCrime
        case .relax: return strings.discoverMoodRelax
        }
    }

    func searchTerm(language: AppLanguage) -> String {
        switch (self, language) {
        case (.english, .japanese): return "英語学習 ポッドキャスト"
        case (.english, .vietnamese): return "podcast học tiếng Anh"
        case (.english, _): return "english learning podcast"
        case (.business, .japanese): return "ビジネス ポッドキャスト"
        case (.business, .vietnamese): return "podcast kinh doanh"
        case (.business, _): return "business podcast"
        case (.news, .japanese): return "ニュース ポッドキャスト"
        case (.news, .vietnamese): return "podcast tin tức"
        case (.news, _): return "news podcast"
        case (.comedy, .japanese): return "お笑い トーク ポッドキャスト"
        case (.comedy, .vietnamese): return "podcast hài hước"
        case (.comedy, _): return "comedy podcast"
        case (.trueCrime, .japanese): return "犯罪 ミステリー ポッドキャスト"
        case (.trueCrime, .vietnamese): return "podcast tội phạm"
        case (.trueCrime, _): return "true crime podcast"
        case (.relax, .japanese): return "眠れる リラックス ポッドキャスト"
        case (.relax, .vietnamese): return "podcast thư giãn ngủ"
        case (.relax, _): return "sleep relaxation podcast"
        }
    }
}

// MARK: - iTunes Service

struct ITunesPodcastSearchService: Sendable {

    func search(term: String, country: String, limit: Int = 20) async throws -> [PodcastSearchResult] {
        guard ThirdPartyDataConsent.isGranted else { throw PodcastSearchConsentError() }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=podcast&limit=\(limit)&country=\(country)") else {
            return []
        }
        let response: PodcastSearchResponse = try await fetchJSON(from: url)
        return response.results
    }

    func fetchTopPodcasts(country: String, limit: Int = 50) async throws -> [PodcastSearchResult] {
        guard ThirdPartyDataConsent.isGranted else { throw PodcastSearchConsentError() }
        guard let url = URL(string: "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(limit)/json") else {
            return []
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let ids = try parseTopChartIDs(from: data)
        guard !ids.isEmpty else { return [] }
        return try await lookup(ids: ids, country: country)
    }

    func lookup(ids: [Int], country: String = "us") async throws -> [PodcastSearchResult] {
        guard ThirdPartyDataConsent.isGranted else { throw PodcastSearchConsentError() }
        guard !ids.isEmpty else { return [] }
        let idList = ids.map(String.init).joined(separator: ",")
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idList)&entity=podcast&country=\(country)") else {
            return []
        }
        let response: PodcastSearchResponse = try await fetchJSON(from: url)
        return response.results.filter { $0.feedUrl != nil }
    }

    // MARK: - Private

    private func fetchJSON<T: Decodable>(from url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseTopChartIDs(from data: Data) throws -> [Int] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entry = feed["entry"] else {
            return []
        }
        let entries: [[String: Any]]
        if let array = entry as? [[String: Any]] {
            entries = array
        } else if let single = entry as? [String: Any] {
            entries = [single]
        } else {
            return []
        }
        return entries.compactMap { item in
            guard let idBlock = item["id"] as? [String: Any],
                  let attrs = idBlock["attributes"] as? [String: Any],
                  let idString = attrs["im:id"] as? String,
                  let id = Int(idString) else { return nil }
            return id
        }
    }
}

extension AppLanguage {
    var itunesCountryCode: String {
        switch self {
        case .japanese: return "jp"
        case .vietnamese: return "vn"
        case .english: return "us"
        }
    }
}
