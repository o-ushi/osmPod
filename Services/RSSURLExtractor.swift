import Foundation

enum RSSURLExtractor {

    private static let urlPattern = #"https?://[^\s\]\)\"'<>]+"#

    static func extractURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            var raw = String(text[swiftRange])
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?）】」\"'"))
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            let normalized = url.absoluteString
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }
}
